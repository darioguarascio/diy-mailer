FROM alpine:3.20

RUN apk add --no-cache postfix postfix-pcre rsyslog bash ca-certificates

COPY main.cf /etc/postfix/main.cf
COPY bounce-handler.sh /usr/local/bin/bounce-handler.sh
COPY start.sh /start.sh

RUN chmod +x /start.sh /usr/local/bin/bounce-handler.sh

EXPOSE 25

ENTRYPOINT ["/start.sh"]
