#!/usr/bin/env bash
# DNS record helpers for check-dns.sh.

fetch_txt_records() {
  local name="$1"
  dig +short TXT "${name}" 2>/dev/null | tr -d '"' || true
}

fetch_spf_record() {
  local domain="$1" txt
  txt="$(fetch_txt_records "${domain}")"
  [ -n "${txt}" ] || return 0
  printf '%s\n' "${txt}" | grep -i 'v=spf1' | head -1 || true
}

# Build SPF TXT, merging with existing record on the apex domain when present.
merge_spf_record() {
  local domain="$1" hostname="$2" server_ip="$3"
  local existing spf

  existing="$(fetch_spf_record "${domain}")"
  if [ -z "${existing}" ]; then
    if [ -n "${server_ip}" ]; then
      printf 'v=spf1 a:%s ip4:%s -all' "${hostname}" "${server_ip}"
    else
      printf 'v=spf1 a:%s ip4:YOUR_SERVER_IP -all' "${hostname}"
    fi
    return 0
  fi

  spf="${existing}"
  spf="$(printf '%s' "${spf}" | sed -E 's/[ ~-]+all$//; s/[[:space:]]+$//')"

  if ! printf '%s' "${spf}" | grep -qF "a:${hostname}"; then
    spf="${spf} a:${hostname}"
  fi
  if [ -n "${server_ip}" ] && ! printf '%s' "${spf}" | grep -qF "ip4:${server_ip}"; then
    spf="${spf} ip4:${server_ip}"
  fi
  spf="${spf} -all"
  spf="$(printf '%s' "${spf}" | sed -E 's/  +/ /g')"
  printf '%s' "${spf}"
}

# Other TXT records on apex (non-SPF), one per line.
fetch_other_apex_txt() {
  local domain="$1" txt
  txt="$(fetch_txt_records "${domain}")"
  [ -n "${txt}" ] || return 0
  printf '%s\n' "${txt}" | grep -vi 'v=spf1' || true
}
