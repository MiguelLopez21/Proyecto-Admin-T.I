#!/bin/sh
# Genera /etc/chrony/chrony.conf a partir de la plantilla y arranca chronyd en primer plano.
set -eu

: "${ALLOW_SUBNET:?Falta ALLOW_SUBNET (ej. 172.20.10.0/28; se aceptan varias separadas por coma)}"
AJUSTAR_RELOJ="${AJUSTAR_RELOJ:-true}"

# Una línea "allow" por cada subred (separadas por coma o espacio).
ALLOW_LINES=""
for red in $(echo "$ALLOW_SUBNET" | tr ',' ' '); do
  ALLOW_LINES="${ALLOW_LINES}allow ${red}
"
done

awk -v lines="$ALLOW_LINES" '{ if ($0 == "${ALLOW_LINES}") printf "%s", lines; else print }' \
  /etc/chrony/chrony.conf.template > /etc/chrony/chrony.conf

mkdir -p /run/chrony /var/lib/chrony
chown chrony:chrony /run/chrony /var/lib/chrony
chmod 750 /run/chrony

echo "[ntp] Subredes permitidas: $(echo "$ALLOW_SUBNET" | tr ',' ' ')"

OPCIONES="-d -u chrony -f /etc/chrony/chrony.conf"
if [ "$AJUSTAR_RELOJ" = "false" ]; then
  # Modo prueba: sirve hora pero no toca el reloj del host (no necesita SYS_TIME).
  echo "[ntp] AJUSTAR_RELOJ=false: chronyd no modificará el reloj del sistema (-x)."
  OPCIONES="$OPCIONES -x"
fi

echo "[ntp] Iniciando: chronyd $OPCIONES"
# -d: primer plano, logs por stderr (se ven en la pestaña Logs de Dokploy).
exec chronyd $OPCIONES
