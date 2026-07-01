#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env
fi

# shellcheck disable=SC1091
source scripts/lib/domains.sh
# shellcheck disable=SC1091
source scripts/lib/dkim.sh

FILTER_DOMAIN="${1:-}"

show_domain() {
  local domain="$1" selector="$2"
  local record

  echo "--- ${domain} (selector: ${selector}) ---"
  echo "TXT record host: ${selector}._domainkey.${domain}"

  record="$(get_dkim_public_record "${domain}" "${selector}" 2>/dev/null || true)"
  if [ -n "${record}" ]; then
    printf '%s\n' "${record}"
    return 0
  fi

  echo "error: DKIM key not found for ${domain}." >&2
  echo "  Ensure ${domain} is in domains.conf, then run:" >&2
  echo "    docker compose up -d --force-recreate opendkim" >&2
  return 1
}

found=0
errors=0
load_domain_lines
for _line in "${DOMAIN_LINES[@]}"; do
  IFS='|' read -r domain _hostname selector <<< "${_line}"
  if [ -n "${FILTER_DOMAIN}" ] && [ "${domain}" != "${FILTER_DOMAIN}" ]; then
    continue
  fi
  if ! show_domain "${domain}" "${selector}"; then
    errors=1
  fi
  echo
  found=1
done

if [ "${found}" -eq 0 ]; then
  if [ -n "${FILTER_DOMAIN}" ]; then
    echo "error: domain '${FILTER_DOMAIN}' not found in domains.conf" >&2
  else
    echo "error: no domains configured — run scripts/setup.sh or create domains.conf" >&2
  fi
  exit 1
fi

exit "${errors}"
