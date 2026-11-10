FROM alpine:3.24


RUN apk upgrade --no-cache && \
    apk add --no-cache su-exec curl openssl ca-certificates docker lego bash idn2-utils

COPY exec.sh /srv/exec.sh
RUN chmod +x /srv/exec.sh

ENTRYPOINT ["/srv/exec.sh"]
