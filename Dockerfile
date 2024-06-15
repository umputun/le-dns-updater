FROM alpine:3.20


RUN apk add --update su-exec curl openssl ca-certificates docker lego bash

COPY exec.sh /srv/exec.sh
RUN chmod +x /srv/exec.sh

ENTRYPOINT ["/srv/exec.sh"]
