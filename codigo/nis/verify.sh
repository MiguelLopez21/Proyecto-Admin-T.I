#!/bin/bash
# Uso:
#   bash verify.sh server                 (en srv-ecopetrol)
#   bash verify.sh client SERVER_IP       (en el cliente Linux, p. ej. cli-icpet)
# Variables opcionales: NIS_DOMAIN (por defecto ecopetrol.local).
# En "client", si DEMO_PASSWORD está definida y sshpass está instalado, también prueba el login
# real por SSH (contraseña buena y mala). Si no, imprime el comando para hacerlo a mano.
# Solo hace lecturas; no modifica nada.
set -uo pipefail

MODO="${1:-}"
DOMINIO="${NIS_DOMAIN:-ecopetrol.local}"
DIR="$(cd "$(dirname "$0")" && pwd)"
FALLOS=0

ok()   { echo "[OK]    $1"; }
fallo(){ echo "[FALLA] $1"; FALLOS=$((FALLOS+1)); }
aviso(){ echo "[AVISO] $1"; }

usuarios_esperados() {
  tail -n +2 "$DIR/config/usuarios.csv" | tr -d '\r' | cut -d, -f1 | grep -v '^$'
}

server() {
  local s
  for s in rpcbind ypserv yppasswdd; do
    if systemctl is-active --quiet "$s"; then ok "servicio $s activo"; else fallo "servicio $s no está activo"; fi
  done

  local rpc
  rpc="$(rpcinfo -p localhost 2>&1)"
  if echo "$rpc" | grep -qE '\s834\s+ypserv'; then ok "ypserv en el puerto fijo 834"; else fallo "ypserv no está en 834 (revisar YPSERVARGS en /etc/default/nis)"; fi
  if echo "$rpc" | grep -qE '\s835\s+yppasswdd'; then ok "yppasswdd en el puerto fijo 835"; else fallo "yppasswdd no está en 835 (revisar YPPASSWDDARGS en /etc/default/nis)"; fi

  if [ "$(cat /etc/defaultdomain 2>/dev/null)" = "$DOMINIO" ]; then ok "/etc/defaultdomain = $DOMINIO"; else fallo "/etc/defaultdomain no es $DOMINIO"; fi

  if grep -qE '^[[:space:]]*0\.0\.0\.0[[:space:]]+0\.0\.0\.0' /etc/ypserv.securenets 2>/dev/null; then
    fallo "securenets abre NIS a todo el mundo (0.0.0.0 0.0.0.0)"
  else
    ok "securenets limitado a: $(grep -vE '^\s*(#|$)' /etc/ypserv.securenets 2>/dev/null | awk '{print $2"/"$1}' | paste -sd' ')"
  fi

  local mapa u faltan=""
  mapa="$(ypcat -d "$DOMINIO" -h localhost passwd 2>&1)"
  for u in $(usuarios_esperados); do
    echo "$mapa" | grep -q "^$u:" || faltan="$faltan $u"
  done
  if [ -z "$faltan" ]; then ok "ypcat passwd lista los $(usuarios_esperados | wc -l) usuarios del CSV"; else fallo "faltan en el mapa passwd:$faltan (¿sudo make -C /var/yp?)"; fi

  if echo "$mapa" | awk -F: '$3 < 2000' | grep -q .; then
    fallo "el mapa passwd exporta cuentas con UID < 2000: $(echo "$mapa" | awk -F: '$3 < 2000 {print $1}' | paste -sd' ')"
  else
    ok "el mapa passwd no exporta cuentas del sistema (UID < 2000)"
  fi
}

client() {
  local ip="${2:-}"
  if [ -z "$ip" ]; then echo "Uso: bash verify.sh client SERVER_IP"; exit 2; fi

  if systemctl is-active --quiet ypbind; then ok "servicio ypbind activo"; else fallo "servicio ypbind no está activo"; fi

  local srv
  srv="$(ypwhich 2>&1)"
  if [ "$srv" = "$ip" ] || [ "$srv" = "srv-ecopetrol" ] || getent hosts "$srv" | grep -q "^$ip "; then
    ok "ypwhich: enlazado a $srv"
  else
    fallo "ypwhich devuelve '$srv' (se esperaba $ip)"
  fi

  for k in passwd group shadow; do
    if grep -qE "^$k:.*[[:space:]]nis([[:space:]]|$)" /etc/nsswitch.conf; then ok "nsswitch: $k consulta nis"; else fallo "nsswitch: $k no tiene nis"; fi
  done

  if grep -qs 'IPAddressAllow=any' /etc/systemd/system/systemd-logind.service.d/nis.conf; then
    ok "drop-in de systemd-logind presente (IPAddressAllow=any)"
  else
    fallo "falta el drop-in de systemd-logind: el login de usuarios NIS se cuelga"
  fi

  if [ "$(getent passwd lab.icpet1 | cut -d: -f3)" = "2011" ]; then ok "getent passwd lab.icpet1 → UID 2011"; else fallo "getent passwd lab.icpet1 no devuelve UID 2011"; fi
  if [ "$(getent passwd lab.icpet1 | cut -d: -f6)" = "/home/nis/lab.icpet1" ]; then ok "home de lab.icpet1 = /home/nis/lab.icpet1"; else fallo "el home de lab.icpet1 no es /home/nis/lab.icpet1"; fi
  if id fin.bogota 2>/dev/null | grep -q 'gid=3003(administrativa)'; then ok "id fin.bogota → administrativa(3003)"; else fallo "id fin.bogota no muestra gid=3003(administrativa)"; fi
  if id admin.ti 2>/dev/null | grep -q '3002(icpet)'; then ok "admin.ti pertenece también a icpet (grupos secundarios por NIS)"; else fallo "admin.ti no aparece en el grupo icpet (¿caché de grupos de nscd activa?)"; fi

  # Login real (lo que pide la rúbrica)
  if [ -n "${DEMO_PASSWORD:-}" ] && command -v sshpass >/dev/null; then
    local opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o LogLevel=ERROR)
    local salida
    salida="$(sshpass -p "$DEMO_PASSWORD" ssh "${opts[@]}" lab.icpet1@localhost pwd 2>&1)"
    if [ "$salida" = "/home/nis/lab.icpet1" ]; then ok "login SSH de lab.icpet1 con la contraseña NIS (pwd = $salida)"; else fallo "login SSH de lab.icpet1 falló: $salida"; fi
    if sshpass -p "incorrecta-$$" ssh "${opts[@]}" lab.icpet1@localhost true >/dev/null 2>&1; then
      fallo "una contraseña incorrecta fue aceptada"
    else
      ok "una contraseña incorrecta es rechazada"
    fi
  else
    aviso "login real no probado (falta DEMO_PASSWORD o sshpass). A mano: ssh lab.icpet1@localhost  → pwd = /home/nis/lab.icpet1"
  fi
}

case "$MODO" in
  server) server ;;
  client) client "$@" ;;
  *) echo "Uso: bash verify.sh server | bash verify.sh client SERVER_IP"; exit 2 ;;
esac

echo
if [ "$FALLOS" -eq 0 ]; then echo "Todas las verificaciones pasaron."; exit 0; else echo "$FALLOS verificacion(es) fallaron."; exit 1; fi
