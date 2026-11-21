#!/bin/bash
# Uso:
#   sudo bash verify.sh server                 (en srv-ecopetrol)
#   sudo bash verify.sh client SERVER_IP       (en el cliente Linux con NIS, p. ej. cli-icpet)
# Necesita root: en el servidor para leer los exports; en el cliente para actuar como cada usuario
# NIS (sudo -u) y comprobar los permisos. Solo crea un archivo de prueba y lo borra al final.
set -uo pipefail

MODO="${1:-}"
DOMINIO="${NFS_DOMAIN:-ecopetrol.local}"
FALLOS=0

ok()   { echo "[OK]    $1"; }
fallo(){ echo "[FALLA] $1"; FALLOS=$((FALLOS+1)); }

[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo."; exit 2; }

idmap_ok() {
  if grep -qE "^[[:space:]]*Domain[[:space:]]*=[[:space:]]*$DOMINIO[[:space:]]*$" /etc/idmapd.conf 2>/dev/null; then
    ok "idmapd.conf: Domain = $DOMINIO"
  else
    fallo "idmapd.conf no tiene Domain = $DOMINIO (los dueños saldrían como nobody)"
  fi
}

server() {
  if systemctl is-active --quiet nfs-server; then ok "servicio nfs-server activo"; else fallo "servicio nfs-server no está activo"; fi

  local exp ruta
  exp="$(exportfs -v 2>&1)"
  for ruta in /srv/nfs/ecopetrol /home/nis; do
    if echo "$exp" | grep -q "^$ruta"; then ok "exportado: $ruta"; else fallo "no se exporta $ruta"; fi
  done
  if echo "$exp" | grep -q 'no_root_squash'; then fallo "hay un export con no_root_squash"; else ok "todos los exports con root_squash"; fi

  if ss -tln 2>/dev/null | grep -qE '[:.]2049\s'; then ok "puerto 2049/tcp escuchando"; else fallo "puerto 2049/tcp no escucha"; fi

  local perm
  perm="$(stat -c '%a %U:%G' /srv/nfs/ecopetrol 2>/dev/null)"
  if [ "$perm" = "2770 root:icpet" ]; then ok "/srv/nfs/ecopetrol: $perm (setgid, solo el grupo icpet)"; else fallo "/srv/nfs/ecopetrol tiene '$perm' (se esperaba 2770 root:icpet)"; fi

  idmap_ok
}

client() {
  local ip="${2:-}"
  if [ -z "$ip" ]; then echo "Uso: sudo bash verify.sh client SERVER_IP"; exit 2; fi

  local m
  for m in /mnt/ecopetrol /home/nis; do
    if findmnt -t nfs4 -n -o SOURCE "$m" 2>/dev/null | grep -q "^$ip:"; then ok "montado por NFSv4: $(findmnt -n -o SOURCE "$m") en $m"; else fallo "$m no está montado por NFSv4 desde $ip"; fi
  done
  idmap_ok

  local dir=/mnt/ecopetrol/ensayos
  local f="$dir/verify-$(date +%Y%m%d-%H%M%S)-$$"

  if sudo -u lab.icpet1 touch "$f" 2>/dev/null; then ok "lab.icpet1 crea $f"; else fallo "lab.icpet1 no pudo crear un archivo en $dir"; fi
  # Ojo: root del cliente es "nobody" en el servidor (root_squash) y no puede entrar a una carpeta 2770,
  # así que las comprobaciones sobre el archivo se hacen como lab.icpet1.
  if sudo -u lab.icpet1 test -e "$f"; then
    local dueno
    dueno="$(sudo -u lab.icpet1 stat -c '%U:%G' "$f")"
    if [ "$dueno" = "lab.icpet1:icpet" ]; then ok "dueño del archivo: $dueno (grupo heredado por setgid)"; else fallo "dueño del archivo: $dueno (se esperaba lab.icpet1:icpet; ¿UID o idmapd distintos?)"; fi
    sudo -u lab.icpet1 chmod g+w "$f" 2>/dev/null
    if sudo -u lab.icpet2 sh -c "echo prueba >> '$f'" 2>/dev/null; then ok "lab.icpet2 (mismo grupo) modifica el archivo"; else fallo "lab.icpet2 no pudo modificar el archivo del grupo"; fi
  fi

  if sudo -u fin.bogota ls /mnt/ecopetrol >/dev/null 2>&1; then fallo "fin.bogota (otro grupo) pudo listar /mnt/ecopetrol"; else ok "fin.bogota (administrativa) recibe Permission denied"; fi

  local r="/mnt/ecopetrol/root-squash-$$"
  if touch "$r" 2>/dev/null; then
    fallo "root del cliente pudo escribir en /mnt/ecopetrol (¿no_root_squash?) — dueño: $(stat -c '%U:%G' "$r")"
    rm -f "$r"
  else
    ok "root del cliente no puede escribir en /mnt/ecopetrol (root_squash)"
  fi

  if sudo -u lab.icpet1 test -w /home/nis/lab.icpet1 && ! sudo -u lab.icpet2 ls /home/nis/lab.icpet1 >/dev/null 2>&1; then
    ok "el home NFS de lab.icpet1 es suyo y otro usuario no lo puede leer"
  else
    fallo "permisos del home /home/nis/lab.icpet1 incorrectos (deben ser 700 y del usuario)"
  fi

  sudo -u lab.icpet1 rm -f "$f" 2>/dev/null
}

case "$MODO" in
  server) server ;;
  client) client "$@" ;;
  *) echo "Uso: sudo bash verify.sh server | sudo bash verify.sh client SERVER_IP"; exit 2 ;;
esac

echo
if [ "$FALLOS" -eq 0 ]; then echo "Todas las verificaciones pasaron."; exit 0; else echo "$FALLOS verificacion(es) fallaron."; exit 1; fi
