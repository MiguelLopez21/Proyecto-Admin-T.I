#!/bin/bash
# Uso:
#   bash verify.sh server                 (en el servidor donde corre el contenedor)
#   bash verify.sh client SERVER_IP       (desde un Linux con cups-client)
set -uo pipefail

MODO="${1:-}"
COLA="Ecopetrol-Bogota-PDF"
FALLOS=0

ok()   { echo "[OK]    $1"; }
fallo(){ echo "[FALLO] $1"; FALLOS=$((FALLOS+1)); }

contenedor() {
  docker ps --filter "label=com.docker.compose.service=cups" --format '{{.Names}}' | head -n1
}

server() {
  local c
  c="$(contenedor)"
  if [ -n "$c" ]; then ok "contenedor cups corriendo ($c)"; else fallo "no hay contenedor cups corriendo"; return; fi

  if docker exec "$c" lpstat -r 2>/dev/null | grep -q 'scheduler is running'; then ok "scheduler is running"; else fallo "el scheduler de CUPS no esta corriendo"; fi

  if docker exec "$c" lpstat -p "$COLA" 2>/dev/null | grep -qiE 'idle|enabled'; then ok "cola $COLA activa (idle/enabled)"; else fallo "cola $COLA no esta activa"; fi

  if ss -tlnp 2>/dev/null | grep -q ':631 '; then ok "puerto 631 escuchando"; else fallo "puerto 631 no escucha"; fi
}

client() {
  local ip="${2:-}"
  if [ -z "$ip" ]; then echo "Uso: bash verify.sh client SERVER_IP"; exit 2; fi
  command -v lp >/dev/null || { echo "Instala cups-client (apt install cups-client)"; exit 2; }

  if lpstat -h "$ip:631" -p 2>/dev/null | grep -q "$COLA"; then ok "lpstat lista $COLA"; else fallo "lpstat no lista $COLA"; fi

  local salida
  salida="$(lp -h "$ip:631" -d "$COLA" /etc/hostname 2>&1)"
  if echo "$salida" | grep -q 'request id is'; then ok "trabajo enviado: $salida"; else fallo "lp fallo: $salida"; fi

  echo
  echo "Ahora, en el servidor, confirma que se genero el PDF:"
  echo "  docker exec \$(docker ps --filter label=com.docker.compose.service=cups --format '{{.Names}}' | head -n1) ls -l /var/spool/cups-pdf/ANONYMOUS"
}

case "$MODO" in
  server) server ;;
  client) client "$@" ;;
  *) echo "Uso: bash verify.sh server | bash verify.sh client SERVER_IP"; exit 2 ;;
esac

echo
if [ "$FALLOS" -eq 0 ]; then echo "Todas las verificaciones pasaron."; exit 0; else echo "$FALLOS verificacion(es) fallaron."; exit 1; fi
