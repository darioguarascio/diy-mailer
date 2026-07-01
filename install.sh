#!/usr/bin/env bash
# Bootstrap installer — use as:
#   curl -fsSL https://raw.githubusercontent.com/darioguarascio/diy-mailer/master/install.sh | bash
#   wget -qO- https://raw.githubusercontent.com/darioguarascio/diy-mailer/master/install.sh | bash
set -euo pipefail

REPO_URL="${DIY_MAILER_REPO:-https://github.com/darioguarascio/diy-mailer.git}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/diy-mailer}"

resolve_branch() {
  if [ -n "${DIY_MAILER_BRANCH:-}" ]; then
    echo "${DIY_MAILER_BRANCH}"
    return
  fi
  local detected
  detected="$(
    git ls-remote --symref "${REPO_URL}" HEAD 2>/dev/null \
      | awk '/^ref:/ { sub(/^refs\/heads\//, "", $2); print $2; exit }'
  )"
  echo "${detected:-master}"
}

require_git() {
  if ! command -v git >/dev/null 2>&1; then
    echo "error: git is required. Install git or clone manually:" >&2
    echo "  git clone --depth 1 ${REPO_URL} ${INSTALL_DIR}" >&2
    exit 1
  fi
}

BRANCH="$(resolve_branch)"

echo "==> DIY Mailer installer"
echo "    install dir: ${INSTALL_DIR}"
echo "    repo:        ${REPO_URL} (${BRANCH})"
echo

if [ -d "${INSTALL_DIR}/.git" ]; then
  echo "==> updating existing install"
  git -C "${INSTALL_DIR}" fetch --depth 1 origin "${BRANCH}"
  git -C "${INSTALL_DIR}" checkout "${BRANCH}"
  git -C "${INSTALL_DIR}" pull --ff-only origin "${BRANCH}" 2>/dev/null || \
    git -C "${INSTALL_DIR}" reset --hard "origin/${BRANCH}"
elif [ -d "${INSTALL_DIR}" ] && [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
  echo "==> using existing directory (not a git clone)"
else
  require_git
  echo "==> cloning repository"
  git clone --depth 1 -b "${BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
fi

cd "${INSTALL_DIR}"
chmod +x install.sh scripts/*.sh scripts/lib/*.sh postfix/start.sh opendkim/entrypoint.sh postfix/bounce-handler.sh 2>/dev/null || true
[ -f domains.conf ] || cp domains.conf.example domains.conf

echo "==> starting interactive setup wizard"
# shellcheck disable=SC1091
source scripts/lib/tty.sh
ensure_tty_stdin
exec bash scripts/setup.sh
