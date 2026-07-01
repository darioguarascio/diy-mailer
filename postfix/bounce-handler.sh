#!/usr/bin/env bash
# Pipe target for bounce aliases — logs envelope + headers to BOUNCE_LOG.
set -euo pipefail

LOG="${BOUNCE_LOG:-/var/log/bounces.log}"
{
  echo "===== $(date -Iseconds) bounce ====="
  cat
  echo
} >> "${LOG}" 2>/dev/null || cat >> /var/log/mail.log
