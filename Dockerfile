FROM alpine:3.16.2

RUN apk add --no-cache curl jq grep bash tini && \
    adduser -D myuser && \
    mkdir /config

COPY update_cert.sh /

USER myuser

ENTRYPOINT ["/sbin/tini", "--", "/update_cert.sh"]
