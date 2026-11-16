#!/bin/bash
# Uso:
#   bash verify.sh server               (en el servidor donde corre el contenedor)
#   bash verify.sh client SERVER_IP     (desde un cliente Linux)
# Solo hace lecturas; no modifica nada.
set -uo pipefail

MODO="${1:-}"
FALLOS=0

ok()   { echo "[OK]    $1"; }
fallo(){ echo "[FALLO] $1"; FALLOS=$((FALLOS+1)); }
aviso(){ echo "[AVISO] $1"; }

DOCKER="docker"
if ! docker ps >/dev/null 2>&1; then DOCKER="sudo docker"; fi

contenedor() {
  $DOCKER ps --filter "label=com.docker.compose.service=ntp" --format '{{.Names}}' | head -n1
}

server() {
  local c
  c="$(contenedor)"
  if [ -n "$c" ]; then ok "contenedor ntp corriendo ($c)"; else fallo "no hay contenedor ntp corriendo"; return; fi

  local tracking
  tracking="$($DOCKER exec "$c" chronyc -n tracking 2>&1)"
  if echo "$tracking" | grep -q 'Leap status *: Normal'; then
    ok "chronyc tracking: Leap status Normal ($(echo "$tracking" | grep -E '^Reference ID' | sed 's/ \+/ /g'))"
  else
    fallo "chronyc tracking no muestra 'Leap status : Normal'"
  fi

  if $DOCKER exec "$c" chronyc -n sources 2>/dev/null | grep -q '^\^\*'; then
    ok "chronyc sources: hay una fuente seleccionada (^*)"
  else
    aviso "sin fuente seleccionada (^*): sin internet sirve como 'local stratum 10'"
  fi

  if $DOCKER exec "$c" grep -q '^allow ' /etc/chrony/chrony.conf; then
    ok "chrony.conf tiene allow: $($DOCKER exec "$c" grep '^allow ' /etc/chrony/chrony.conf | awk '{print $2}' | paste -sd' ')"
  else
    fallo "chrony.conf no tiene ninguna línea allow"
  fi

  if ss -uln 2>/dev/null | grep -qE '[:.]123\s'; then ok "puerto 123/udp escuchando"; else fallo "puerto 123/udp no escucha"; fi

  if timedatectl show -p NTP --value 2>/dev/null | grep -qx no; then
    ok "NTP del host desactivado (chrony del contenedor es la única autoridad)"
  else
    fallo "el NTP del host está activo: sudo timedatectl set-ntp false"
  fi
}

client() {
  local ip="${2:-}"
  if [ -z "$ip" ]; then echo "Uso: bash verify.sh client SERVER_IP"; exit 2; fi

  if command -v chronyc >/dev/null; then
    local fuentes
    fuentes="$(chronyc -n sources 2>&1)"
    if echo "$fuentes" | grep -q "$ip"; then
      ok "chronyc sources incluye $ip"
      if echo "$fuentes" | grep -q "^\^\* *$ip"; then ok "$ip es la fuente seleccionada (^*)"; else fallo "$ip todavía no es la fuente seleccionada (^*)"; fi
    else
      fallo "chronyc sources no incluye $ip (revisar /etc/chrony/chrony.conf del cliente)"
    fi
  elif command -v sntp >/dev/null; then
    if sntp "$ip" >/dev/null 2>&1; then ok "sntp $ip responde"; else fallo "sntp $ip no responde"; fi
  elif command -v ntpdate >/dev/null; then
    if ntpdate -q "$ip" >/dev/null 2>&1; then ok "ntpdate -q $ip responde"; else fallo "ntpdate -q $ip no responde"; fi
  else
    echo "Instala chrony (apt install chrony) o sntp para probar"; exit 2
  fi
}

case "$MODO" in
  server) server ;;
  client) client "$@" ;;
  *) echo "Uso: bash verify.sh server | bash verify.sh client SERVER_IP"; exit 2 ;;
esac

echo
if [ "$FALLOS" -eq 0 ]; then echo "Todas las verificaciones pasaron."; exit 0; else echo "$FALLOS verificacion(es) fallaron."; exit 1; fi
