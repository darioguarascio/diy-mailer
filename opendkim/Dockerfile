FROM alpine:3.20

RUN apk add --no-cache opendkim opendkim-utils bash

COPY opendkim.conf /etc/opendkim/opendkim.conf
COPY trusted.hosts /etc/opendkim/trusted.hosts
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 12345

ENTRYPOINT ["/entrypoint.sh"]
