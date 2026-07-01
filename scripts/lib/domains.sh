#!/usr/bin/env bash
# Shared helpers for domains.conf — source from other scripts.

DOMAINS_FILE="${DOMAINS_FILE:-domains.conf}"

# Emit one line per domain: domain|hostname|selector
# Reads domains.conf; falls back to MAIL_DOMAIN / MAIL_HOSTNAME / DKIM_SELECTOR from env.
list_domains() {
  local line domain hostname selector
  if [ -f "${DOMAINS_FILE}" ]; then
    while IFS= read -r line || [ -n "${line}" ]; do
      line="${line%%#*}"
      line="$(echo "${line}" | xargs)"
      [ -z "${line}" ] && continue
      domain="$(echo "${line}" | cut -d'|' -f1 | xargs)"
      hostname="$(echo "${line}" | cut -d'|' -f2 | xargs)"
      selector="$(echo "${line}" | cut -d'|' -f3 | xargs)"
      [ -z "${domain}" ] && continue
      [ -z "${hostname}" ] && hostname="smtp.mail.${domain}"
      [ -z "${selector}" ] && selector="mail"
      printf '%s|%s|%s\n' "${domain}" "${hostname}" "${selector}"
    done < "${DOMAINS_FILE}"
    return 0
  fi

  domain="${MAIL_DOMAIN:-${DKIM_DOMAIN:-}}"
  if [ -z "${domain}" ]; then
    return 1
  fi
  hostname="${MAIL_HOSTNAME:-smtp.mail.${domain}}"
  selector="${DKIM_SELECTOR:-mail}"
  printf '%s|%s|%s\n' "${domain}" "${hostname}" "${selector}"
}

primary_domain() {
  list_domains | head -1 | cut -d'|' -f1
}

primary_hostname() {
  list_domains | head -1 | cut -d'|' -f2
}

has_configured_domains() {
  list_domains 2>/dev/null | grep -q .
}

# Load domains into DOMAIN_LINES[] — avoids stdin theft in nested commands.
load_domain_lines() {
  DOMAIN_LINES=()
  mapfile -t DOMAIN_LINES < <(list_domains)
}
