#!/bin/bash
# Uso:
#   bash verify.sh server                 (en el servidor donde corre el contenedor)
#   bash verify.sh client SERVER_IP       (desde un Linux con smbclient)
# En "client", la clave de prueba se toma de la variable SMB_PASSWORD o se pregunta.
set -uo pipefail

MODO="${1:-}"
FALLOS=0

ok()   { echo "[OK]    $1"; }
fallo(){ echo "[FALLO] $1"; FALLOS=$((FALLOS+1)); }

contenedor() {
  docker ps --filter "label=com.docker.compose.service=samba" --format '{{.Names}}' | head -n1
}

server() {
  local c
  c="$(contenedor)"
  if [ -n "$c" ]; then ok "contenedor samba corriendo ($c)"; else fallo "no hay contenedor samba corriendo"; return; fi

  if docker exec "$c" testparm -s >/dev/null 2>&1; then ok "testparm -s sin errores"; else fallo "testparm -s con errores"; fi

  local n
  n="$(docker exec "$c" pdbedit -L 2>/dev/null | wc -l)"
  if [ "$n" -ge 3 ]; then ok "pdbedit -L lista $n usuarios"; else fallo "pdbedit -L lista $n usuarios (se esperaban 3)"; fi

  if ss -tlnp 2>/dev/null | grep -q ':445 '; then ok "puerto 445 escuchando"; else fallo "puerto 445 no escucha"; fi
}

client() {
  local ip="${2:-}"
  if [ -z "$ip" ]; then echo "Uso: bash verify.sh client SERVER_IP"; exit 2; fi
  command -v smbclient >/dev/null || { echo "Instala smbclient (apt install smbclient)"; exit 2; }

  local clave="${SMB_PASSWORD:-}"
  if [ -z "$clave" ]; then read -rsp "Clave de prueba de los usuarios Samba: " clave; echo; fi

  local salida

  salida="$(smbclient -L "//$ip" -U "fin.bogota%$clave" 2>&1)"
  if echo "$salida" | grep -q 'administrativa'; then ok "fin.bogota ve el recurso 'administrativa'"; else fallo "no se lista 'administrativa'"; fi

  echo "prueba $(date +%s)" > /tmp/prueba_samba.txt
  salida="$(smbclient "//$ip/administrativa" -U "fin.bogota%$clave" -c 'put /tmp/prueba_samba.txt prueba.txt; ls' 2>&1)"
  if echo "$salida" | grep -q 'prueba.txt' && ! echo "$salida" | grep -q 'NT_STATUS'; then ok "fin.bogota escribe y lista"; else fallo "fin.bogota no pudo escribir: $salida"; fi

  salida="$(smbclient "//$ip/administrativa" -U "lab.icpet1%$clave" -c ls 2>&1)"
  if echo "$salida" | grep -qE 'NT_STATUS_(LOGON_FAILURE|ACCESS_DENIED)'; then ok "lab.icpet1 denegado"; else fallo "lab.icpet1 NO fue denegado: $salida"; fi

  salida="$(smbclient -N "//$ip/administrativa" -c ls 2>&1)"
  if echo "$salida" | grep -qE 'NT_STATUS_(LOGON_FAILURE|ACCESS_DENIED)'; then ok "acceso anonimo denegado"; else fallo "acceso anonimo NO fue denegado: $salida"; fi
}

case "$MODO" in
  server) server ;;
  client) client "$@" ;;
  *) echo "Uso: bash verify.sh server | bash verify.sh client SERVER_IP"; exit 2 ;;
esac

echo
if [ "$FALLOS" -eq 0 ]; then echo "Todas las verificaciones pasaron."; exit 0; else echo "$FALLOS verificacion(es) fallaron."; exit 1; fi
