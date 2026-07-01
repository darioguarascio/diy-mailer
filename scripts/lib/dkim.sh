#!/usr/bin/env bash
# DKIM public key helpers.

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose.sh"

dkim_txt_path() {
  printf '.data/dkim/%s/%s.txt' "$1" "$2"
}

# Print DNS-ready DKIM TXT value (v=DKIM1; k=rsa; p=...) from opendkim-genkey output.
format_dkim_record() {
  local raw="$1"
  local flat p

  flat="$(printf '%s' "${raw}" | tr -d '\n\t' | sed 's/  */ /g')"
  p="$(printf '%s' "${flat}" | grep -oE 'p=[A-Za-z0-9+/=]+' | head -1 || true)"
  if [ -n "${p}" ]; then
    printf 'v=DKIM1; k=rsa; %s' "${p}"
    return 0
  fi

  if printf '%s' "${flat}" | grep -q 'v=DKIM1'; then
    printf '%s' "${flat}" | sed -E 's/.*(v=DKIM1[^)]*).*/\1/; s/"//g; s/ *$//'
    return 0
  fi
  return 1
}

read_dkim_file() {
  local path="$1"
  [ -f "${path}" ] || return 1
  format_dkim_record "$(cat "${path}")"
}

read_dkim_from_container() {
  local domain="$1" selector="$2"
  local compose out

  compose="$(resolve_compose)" || return 1
  if [ -z "$(${compose} ps -q opendkim 2>/dev/null || true)" ]; then
    return 1
  fi

  out="$(${compose} exec -T opendkim cat "/etc/opendkim/keys/${domain}/${selector}.txt" 2>/dev/null || true)"
  [ -n "${out}" ] || return 1
  format_dkim_record "${out}"
}

ensure_opendkim_keys() {
  local compose
  compose="$(resolve_compose)" || return 1
  ${compose} up -d --force-recreate opendkim >/dev/null 2>&1 || return 1
  sleep 2
  return 0
}

# Print DKIM public record to stdout, or return non-zero.
get_dkim_public_record() {
  local domain="$1" selector="$2"
  local path record

  path="$(dkim_txt_path "${domain}" "${selector}")"
  record="$(read_dkim_file "${path}" 2>/dev/null || true)"
  if [ -n "${record}" ]; then
    printf '%s' "${record}"
    return 0
  fi

  record="$(read_dkim_from_container "${domain}" "${selector}" 2>/dev/null || true)"
  if [ -n "${record}" ]; then
    printf '%s' "${record}"
    return 0
  fi

  ensure_opendkim_keys || return 1

  record="$(read_dkim_file "${path}" 2>/dev/null || true)"
  if [ -n "${record}" ]; then
    printf '%s' "${record}"
    return 0
  fi

  record="$(read_dkim_from_container "${domain}" "${selector}" 2>/dev/null || true)"
  if [ -n "${record}" ]; then
    printf '%s' "${record}"
    return 0
  fi

  return 1
}
