#!/bin/bash
# Entrypoint de CUPS. Idempotente: se puede ejecutar en cada arranque.
set -euo pipefail

: "${CUPS_ADMIN_USER:=admin.ti}"
: "${CUPS_ADMIN_PASSWORD:?Falta CUPS_ADMIN_PASSWORD}"
: "${ALLOW_SUBNET:?Falta ALLOW_SUBNET (por ejemplo 192.168.1.0/24)}"

COLA="Ecopetrol-Bogota-PDF"

# 1. Configuracion: si el volumen /etc/cups esta vacio o incompleto, copiar la de la imagen
#    (sin sobrescribir lo que ya exista, como printers.conf). Luego generar los archivos propios.
mkdir -p /etc/cups /run/cups /var/spool/cups /var/log/cups
cp -an /opt/cups-default/. /etc/cups/
sed "s|\${ALLOW_SUBNET}|${ALLOW_SUBNET}|g" /opt/cups-templates/cupsd.conf > /etc/cups/cupsd.conf
cp /opt/cups-templates/cups-pdf.conf /etc/cups/cups-pdf.conf

# Logs a stderr y administradores del sistema (cups-files.conf)
touch /etc/cups/cups-files.conf
sed -i -E '/^(ErrorLog|AccessLog|PageLog|SystemGroup)[[:space:]]/d' /etc/cups/cups-files.conf
cat >> /etc/cups/cups-files.conf <<'EOF'
SystemGroup lpadmin root
ErrorLog stderr
AccessLog stderr
PageLog stderr
EOF

# 2. Usuario administrador y su clave
getent group lpadmin >/dev/null || groupadd -r lpadmin
if ! id "${CUPS_ADMIN_USER}" >/dev/null 2>&1; then
  useradd -M -s /usr/sbin/nologin -G lpadmin "${CUPS_ADMIN_USER}" 2>/dev/null \
    || useradd --badname -M -s /usr/sbin/nologin -G lpadmin "${CUPS_ADMIN_USER}"
fi
usermod -aG lpadmin "${CUPS_ADMIN_USER}"
echo "${CUPS_ADMIN_USER}:${CUPS_ADMIN_PASSWORD}" | chpasswd

# Carpetas de salida de cups-pdf
mkdir -p /var/spool/cups-pdf/ANONYMOUS /var/spool/cups-pdf/SPOOL
chmod 0777 /var/spool/cups-pdf/ANONYMOUS

# 3. Arrancar cupsd en segundo plano y esperar a que responda
cupsd -f &
CUPSD_PID=$!
trap 'kill -TERM "${CUPSD_PID}" 2>/dev/null || true' TERM INT

for i in $(seq 1 30); do
  if lpstat -r 2>/dev/null | grep -q "scheduler is running"; then break; fi
  sleep 1
  if [ "$i" -eq 30 ]; then echo "[entrypoint] ERROR: cupsd no responde" >&2; exit 1; fi
done
echo "[entrypoint] cupsd listo"

# 4. Crear la cola si no existe
if ! lpstat -p "${COLA}" >/dev/null 2>&1; then
  PPD="$(lpinfo -m 2>/dev/null | grep -i 'cups-pdf' | head -n1 | awk '{print $1}')"
  PPD="${PPD:-lsb/usr/cups-pdf/CUPS-PDF_opt.ppd}"
  echo "[entrypoint] creando cola ${COLA} con PPD ${PPD}"
  lpadmin -p "${COLA}" -E -v cups-pdf:/ -m "${PPD}" \
    -L "Sede Bogota - Piso TI" -D "Impresora virtual PDF Ecopetrol" \
    -o printer-is-shared=true
fi

# 5. Cola predeterminada. No usar cupsctl --remote-any ni --share-printers:
#    reescriben cupsd.conf y borran la restriccion por subred.
lpadmin -d "${COLA}"

# 6. Mantener el contenedor en primer plano (logs por stdout/stderr)
wait "${CUPSD_PID}"
