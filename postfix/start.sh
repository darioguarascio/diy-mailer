#!/usr/bin/env bash
set -euo pipefail

MAIL_DOMAIN="${MAIL_DOMAIN:?MAIL_DOMAIN is required}"
MAIL_HOSTNAME="${MAIL_HOSTNAME:?MAIL_HOSTNAME is required}"
SMTP_RELAY_MYNETWORKS="${SMTP_RELAY_MYNETWORKS:-127.0.0.0/8 172.16.0.0/12 172.20.0.0/16 10.0.0.0/8}"
DKIM_MILTER_HOST="${DKIM_MILTER_HOST:-opendkim}"
DKIM_MILTER_PORT="${DKIM_MILTER_PORT:-12345}"
MAIL_INET_PROTOCOLS="${MAIL_INET_PROTOCOLS:-ipv4}"
BOUNCE_LOG="${BOUNCE_LOG:-/var/log/bounces.log}"

postconf -e "mydomain = ${MAIL_DOMAIN}"
postconf -e "myhostname = ${MAIL_HOSTNAME}"
postconf -e "myorigin = \$mydomain"
postconf -e "mynetworks = ${SMTP_RELAY_MYNETWORKS}"
postconf -e "inet_protocols = ${MAIL_INET_PROTOCOLS}"
postconf -e "smtpd_milters = inet:${DKIM_MILTER_HOST}:${DKIM_MILTER_PORT}"
postconf -e "non_smtpd_milters = \$smtpd_milters"
postconf -e "maillog_file = /var/log/mail.log"

mkdir -p /var/log /var/spool/postfix/etc /var/lib/postfix
cp -f /etc/resolv.conf /var/spool/postfix/etc/resolv.conf
touch /var/log/mail.log "${BOUNCE_LOG}"

# Bounce alias: if inbound delivery is enabled, pipe bounces to handler.
# Outbound-only setups receive bounces via MX elsewhere (see README).
postalias lmdb:/etc/postfix/aliases || true

postfix check
exec postfix start-fg
