# Servidor NTP de srv-ecopetrol: chrony sobre Alpine 3.20.
FROM alpine:3.20

RUN apk add --no-cache chrony tzdata \
 && rm -f /etc/chrony/chrony.conf

COPY config/chrony.conf.template /etc/chrony/chrony.conf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

EXPOSE 123/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD chronyc -n tracking >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
