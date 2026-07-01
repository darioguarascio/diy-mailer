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
source scripts/lib/dns.sh
# shellcheck disable=SC1091
source scripts/lib/dkim.sh

SERVER_IP="${SERVER_IP:-}"
GENERATE=0
FILTER_DOMAIN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --generate) GENERATE=1 ;;
    --domain) FILTER_DOMAIN="${2:-}"; shift ;;
    *) echo "usage: $0 [--generate] [--domain DOMAIN]" >&2; exit 1 ;;
  esac
  shift
done

if ! list_domains >/dev/null 2>&1; then
  echo "error: no domains configured — create domains.conf or set MAIL_DOMAIN in .env" >&2
  exit 1
fi

if [ -z "${SERVER_IP}" ]; then
  SERVER_IP="$(curl -fsS -4 --max-time 3 https://api.ipify.org 2>/dev/null || true)"
fi

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

generate_records() {
  local domain="$1" hostname="$2" selector="$3"
  local spf dkim other_txt existing_spf

  spf="$(merge_spf_record "${domain}" "${hostname}" "${SERVER_IP}")"
  existing_spf="$(fetch_spf_record "${domain}")"
  dkim="$(get_dkim_public_record "${domain}" "${selector}" 2>/dev/null || true)"

  echo
  bold "DNS records for ${domain}"
  echo
  echo "| Type | Name                              | Value"
  echo "| ---- | --------------------------------- | -----"
  if [ -n "${SERVER_IP}" ]; then
    echo "| A    | ${hostname}                       | ${SERVER_IP}"
  else
    echo "| A    | ${hostname}                       | <your-server-public-IP>"
  fi

  if [ "${hostname}" != "${domain}" ]; then
    local helo_spf
    helo_spf="$(fetch_spf_record "${hostname}" 2>/dev/null || true)"
    if [ -z "${helo_spf}" ]; then
      if [ -n "${SERVER_IP}" ]; then
        echo "| TXT  | ${hostname}                       | v=spf1 a ip4:${SERVER_IP} -all  *(HELO — publish once)*"
      else
        echo "| TXT  | ${hostname}                       | v=spf1 a ip4:YOUR_IP -all  *(HELO — publish once)*"
      fi
    fi
  fi

  if [ -n "${existing_spf}" ]; then
    echo "| TXT  | ${domain}                         | ${spf}  *(merged with existing SPF)*"
  else
    echo "| TXT  | ${domain}                         | ${spf}"
  fi

  local other_lines=()
  mapfile -t other_lines < <(fetch_other_apex_txt "${domain}")
  for other_txt in "${other_lines[@]}"; do
    [ -z "${other_txt}" ] && continue
    echo "| TXT  | ${domain}                         | ${other_txt}  *(existing — keep)*"
  done

  if [ -n "${dkim}" ]; then
    echo "| TXT  | ${selector}._domainkey.${domain}   | ${dkim}"
  else
    echo "| TXT  | ${selector}._domainkey.${domain}   | <run: docker compose up -d --force-recreate opendkim>"
  fi
  echo "| TXT  | _dmarc.${domain}                  | v=DMARC1; p=none; rua=mailto:dmarc@${domain}; pct=100"
  echo
  echo "Note: multiple TXT records on ${domain} are allowed — keep existing records and update SPF as shown."
  echo
  echo "Optional (inbound / bounces via your email provider):"
  echo "| MX   | ${domain}                         | per your provider's documentation"
}

check_domain() {
  local domain="$1" hostname="$2" selector="$3"

  bold "DNS check for ${domain}"
  echo

  local a_ip ptr spf dkim dmarc mx merged_spf

  a_ip="$(dig +short A "${hostname}" 2>/dev/null | head -1 || true)"
  if [ -n "${a_ip}" ]; then
    ok "A ${hostname} → ${a_ip}"
  else
    fail "A ${hostname} — not found"
  fi

  if [ -n "${a_ip}" ]; then
    ptr="$(dig +short -x "${a_ip}" 2>/dev/null | sed 's/\.$//' || true)"
    if [ -n "${ptr}" ] && [ "${ptr}" = "${hostname}" ]; then
      ok "PTR ${a_ip} → ${ptr}"
    elif [ -n "${ptr}" ]; then
      warn "PTR ${a_ip} → ${ptr} (expected ${hostname})"
    else
      warn "PTR missing for ${a_ip} — ask your hoster to set rDNS to ${hostname}"
    fi
  fi

  spf="$(fetch_spf_record "${domain}")"
  merged_spf="$(merge_spf_record "${domain}" "${hostname}" "${SERVER_IP}")"
  if [ -n "${spf}" ]; then
    if [ "${spf}" = "${merged_spf}" ]; then
      ok "SPF ${domain}: ${spf}"
    else
      warn "SPF ${domain}: ${spf}"
      warn "Suggested merge: ${merged_spf}"
    fi
  else
    fail "SPF not found on ${domain} — suggested: ${merged_spf}"
  fi

  dkim="$(dig +short TXT "${selector}._domainkey.${domain}" 2>/dev/null | tr -d '\"' || true)"
  if echo "${dkim}" | grep -q 'v=DKIM1'; then
    ok "DKIM ${selector}._domainkey.${domain} present"
  else
    fail "DKIM ${selector}._domainkey.${domain} — not found"
  fi

  dmarc="$(dig +short TXT "_dmarc.${domain}" 2>/dev/null | tr -d '\"' || true)"
  if echo "${dmarc}" | grep -q 'v=DMARC1'; then
    ok "DMARC _dmarc.${domain}: ${dmarc}"
  else
    warn "DMARC not found — add _dmarc.${domain} (start with p=none)"
  fi

  mx="$(dig +short MX "${domain}" 2>/dev/null || true)"
  if [ -n "${mx}" ]; then
    ok "MX ${domain}: ${mx}"
  else
    warn "No MX — fine for send-only; needed to receive bounces at @${domain}"
  fi
  echo
}

if [ "${GENERATE}" -eq 1 ]; then
  bold "Publish these DNS records"
  load_domain_lines
  for _line in "${DOMAIN_LINES[@]}"; do
    IFS='|' read -r domain hostname selector <<< "${_line}"
    if [ -n "${FILTER_DOMAIN}" ] && [ "${domain}" != "${FILTER_DOMAIN}" ]; then
      continue
    fi
    generate_records "${domain}" "${hostname}" "${selector}"
  done
  exit 0
fi

load_domain_lines
for _line in "${DOMAIN_LINES[@]}"; do
  IFS='|' read -r domain hostname selector <<< "${_line}"
  if [ -n "${FILTER_DOMAIN}" ] && [ "${domain}" != "${FILTER_DOMAIN}" ]; then
    continue
  fi
  check_domain "${domain}" "${hostname}" "${selector}"
done

bold "Mail-tester"
echo "  Send test to the address at https://www.mail-tester.com and aim for 9+/10"
