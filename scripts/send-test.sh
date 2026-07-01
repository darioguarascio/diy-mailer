#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [ -f .env ]; then
  # shellcheck disable=SC1091
  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [ -z "${line}" ] && continue
    var="${line%%=*}"
    [ -z "${var}" ] && continue
    if [ -z "${!var:-}" ]; then
      export "${line?}"
    fi
  done < .env
fi

TO="${1:-}"
if [ -z "${TO}" ]; then
  read -r -p "Recipient email: " TO
fi

HOST="${SMTP_HOST:-127.0.0.1}"
PORT="${SMTP_PORT:-25}"
FROM="${EMAIL_FROM:-noreply@example.com}"
FROM_NAME="${EMAIL_FROM_NAME:-}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required for test send" >&2
  exit 1
fi

export FROM FROM_NAME TO HOST PORT
python3 - <<'PY'
import os
import smtplib
from email.message import EmailMessage
from email.utils import formatdate, make_msgid

from_addr = os.environ["FROM"]
from_name = os.environ.get("FROM_NAME", "")
domain = from_addr.split("@", 1)[-1]

msg = EmailMessage()
msg["Subject"] = "DIY Mailer test"
msg["From"] = f"{from_name} <{from_addr}>" if from_name else from_addr
msg["To"] = os.environ["TO"]
msg["Date"] = formatdate(localtime=True)
msg["Message-ID"] = make_msgid(domain=domain)
msg.set_content("If you received this, SMTP + DKIM signing is working.")
msg.add_alternative(
    "<p>If you received this, <strong>SMTP + DKIM</strong> is working.</p>",
    subtype="html",
)

host = os.environ["HOST"]
port = int(os.environ["PORT"])
with smtplib.SMTP(host, port, timeout=15) as s:
    s.send_message(msg)
print(f"sent to {os.environ['TO']} via {host}:{port}")
PY

echo "Check headers for DKIM-Signature. For deliverability score: https://www.mail-tester.com"
