#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# shellcheck disable=SC1091
source scripts/lib/domains.sh
# shellcheck disable=SC1091
source scripts/lib/tty.sh

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
prompt() {
  local var="$1" default="$2" label="$3"
  local value
  if [ -r /dev/tty ]; then
    read -r -p "${label} [${default}]: " value </dev/tty
  else
    read -r -p "${label} [${default}]: " value
  fi
  printf -v "${var}" '%s' "${value:-$default}"
}

ensure_tty_stdin

if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env
fi

bold "Add a sending domain"
echo "Each domain gets its own DKIM key pair and DNS records."
echo

DEFAULT_HOSTNAME="${MAIL_HOSTNAME:-}"
if [ -z "${DEFAULT_HOSTNAME}" ] && has_configured_domains 2>/dev/null; then
  DEFAULT_HOSTNAME="$(primary_hostname)"
fi
[ -z "${DEFAULT_HOSTNAME}" ] && DEFAULT_HOSTNAME="smtp.mail.example.com"

prompt DOMAIN "example.com" "Domain name"
prompt HOSTNAME "${DEFAULT_HOSTNAME}" "Shared SMTP hostname (A record + PTR — same for all domains)"
prompt SELECTOR "mail" "DKIM selector"

if [ -f domains.conf ] && grep -qE "^${DOMAIN}\|" domains.conf 2>/dev/null; then
  echo "error: ${DOMAIN} is already in domains.conf" >&2
  exit 1
fi

if [ ! -f domains.conf ]; then
  echo "# domain|hostname|selector" > domains.conf
fi
echo "${DOMAIN}|${HOSTNAME}|${SELECTOR}" >> domains.conf

# shellcheck disable=SC1091
source scripts/lib/compose.sh

bold "Regenerating DKIM keys for all domains"
compose="$(resolve_compose)" || { echo "error: docker compose is required" >&2; exit 1; }
${compose} up -d --force-recreate opendkim
sleep 2

bold "DKIM record for ${DOMAIN}"
bash scripts/show-dkim.sh "${DOMAIN}"

echo
bold "DNS records for ${DOMAIN}"
DOMAINS_FILE=domains.conf bash scripts/check-dns.sh --generate --domain "${DOMAIN}"
