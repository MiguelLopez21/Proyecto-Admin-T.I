FROM alpine:3.20

# Samba (servidor SMB), utilidades (smbpasswd, pdbedit, testparm), tini (PID 1) y bash
RUN apk add --no-cache samba samba-common-tools tini bash

COPY config/smb.conf /etc/samba/smb.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 445

ENTRYPOINT ["/sbin/tini","--","/entrypoint.sh"]
