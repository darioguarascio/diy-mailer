#!/usr/bin/env bash
# Reattach stdin when the script was piped (curl | bash).

ensure_tty_stdin() {
  if [ -t 0 ]; then
    return 0
  fi
  if [ -r /dev/tty ]; then
    exec 0</dev/tty
    return 0
  fi
  echo "error: interactive setup requires a terminal." >&2
  echo "  curl -fsSL .../install.sh -o install.sh && bash install.sh" >&2
  echo "  cd diy-mailer && bash scripts/setup.sh" >&2
  exit 1
}

read_tty() {
  local _prompt="$1"
  local _var="$2"
  local _value
  if [ -r /dev/tty ]; then
    read -r -p "${_prompt}" _value </dev/tty
  else
    read -r -p "${_prompt}" _value
  fi
  printf -v "${_var}" '%s' "${_value}"
}
