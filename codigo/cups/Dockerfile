FROM debian:12-slim

ARG CUPS_ADMIN_USER=admin.ti

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      cups cups-client cups-bsd printer-driver-cups-pdf tini \
 && rm -rf /var/lib/apt/lists/*

# Grupo de administradores de CUPS y usuario admin (sin shell, solo para autenticarse en CUPS).
# useradd valida el nombre de forma estricta; se intentan alternativas por el punto en "admin.ti".
RUN getent group lpadmin >/dev/null || groupadd -r lpadmin; \
    useradd -M -s /usr/sbin/nologin -G lpadmin "${CUPS_ADMIN_USER}" 2>/dev/null \
 || useradd --badname -M -s /usr/sbin/nologin -G lpadmin "${CUPS_ADMIN_USER}" 2>/dev/null \
 || true

# Copia de la configuracion por defecto de la imagen y plantillas propias
RUN cp -a /etc/cups /opt/cups-default
COPY config/cupsd.conf /opt/cups-templates/cupsd.conf
COPY config/cups-pdf.conf /opt/cups-templates/cups-pdf.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 631

ENTRYPOINT ["/usr/bin/tini","--","/entrypoint.sh"]
