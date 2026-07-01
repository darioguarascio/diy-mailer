#!/usr/bin/env bash
set -euo pipefail

DOMAINS_FILE="/etc/opendkim/domains.conf"
DEFAULT_SELECTOR="${DKIM_SELECTOR:-mail}"

generate_key() {
  local domain="$1" selector="$2"
  local key_dir="/etc/opendkim/keys/${domain}"
  local private_key="${key_dir}/${selector}.private"

  mkdir -p "${key_dir}"
  if [ ! -f "${private_key}" ]; then
    echo "Generating DKIM key for ${domain} (selector: ${selector})"
    opendkim-genkey -D "${key_dir}" -d "${domain}" -s "${selector}"
    mv "${key_dir}/${selector}.private" "${private_key}"
  fi
  chown opendkim:opendkim "${private_key}"
  chmod 600 "${private_key}"
  echo "${private_key}"
}

print_dkim_record() {
  local domain="$1" selector="$2"
  local public_txt="/etc/opendkim/keys/${domain}/${selector}.txt"

  echo
  echo "================================================================"
  echo " DKIM DNS record — publish as TXT on:"
  echo "   ${selector}._domainkey.${domain}"
  echo "================================================================"
  if [ -f "${public_txt}" ]; then
    tr -d '\n\t' < "${public_txt}" | sed 's/  */ /g'
    echo
  else
    echo "Public key file not found: ${public_txt}" >&2
  fi
  echo "================================================================"
}

build_tables_from_line() {
  local line="$1"
  local domain hostname selector private_key dkim_id

  line="${line%%#*}"
  line="$(echo "${line}" | xargs)"
  [ -z "${line}" ] && return 0

  domain="$(echo "${line}" | cut -d'|' -f1 | xargs)"
  hostname="$(echo "${line}" | cut -d'|' -f2 | xargs)"
  selector="$(echo "${line}" | cut -d'|' -f3 | xargs)"
  [ -z "${domain}" ] && return 0
  [ -z "${selector}" ] && selector="${DEFAULT_SELECTOR}"

  private_key="$(generate_key "${domain}" "${selector}")"
  dkim_id="${selector}._domainkey.${domain}"

  echo "${dkim_id} ${domain}:${selector}:${private_key}" >> /etc/opendkim/KeyTable
  echo "*@${domain} ${dkim_id}" >> /etc/opendkim/SigningTable
  print_dkim_record "${domain}" "${selector}"
}

mkdir -p /run/opendkim /etc/opendkim/keys
chown -R opendkim:opendkim /run/opendkim /etc/opendkim/keys

: > /etc/opendkim/KeyTable
: > /etc/opendkim/SigningTable

if [ -f "${DOMAINS_FILE}" ] && grep -qvE '^\s*(#|$)' "${DOMAINS_FILE}" 2>/dev/null; then
  while IFS= read -r line || [ -n "${line}" ]; do
    build_tables_from_line "${line}"
  done < "${DOMAINS_FILE}"
elif [ -n "${DKIM_DOMAIN:-}" ] || [ -n "${MAIL_DOMAIN:-}" ]; then
  domain="${DKIM_DOMAIN:-${MAIL_DOMAIN}}"
  selector="${DEFAULT_SELECTOR}"
  private_key="$(generate_key "${domain}" "${selector}")"
  dkim_id="${selector}._domainkey.${domain}"
  echo "${dkim_id} ${domain}:${selector}:${private_key}" > /etc/opendkim/KeyTable
  echo "*@${domain} ${dkim_id}" > /etc/opendkim/SigningTable
  print_dkim_record "${domain}" "${selector}"
else
  echo "error: configure domains in domains.conf or set DKIM_DOMAIN" >&2
  exit 1
fi

exec opendkim -f -x /etc/opendkim/opendkim.conf
