#!/usr/bin/env bash
# install.sh: servidor NFSv4 (C, NFS). Requiere NIS ya funcionando. Idempotente.
# Uso: sudo ./install.sh .env
set -euo pipefail

ENV_FILE="${1:-.env}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo."; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "No existe $ENV_FILE (copia .env.example)."; exit 1; }
set -a; source "$ENV_FILE"; set +a
: "${SUBRED:?falta SUBRED}"
: "${NFS_DOMAIN:?falta NFS_DOMAIN}"

echo "== 1. Comprobar que NIS ya funciona =="
getent group icpet | grep -q ':3002:' || { echo "Falta NIS: el grupo icpet (3002) no aparece. Instala NIS primero."; exit 1; }

echo "== 2. Instalar nfs-kernel-server =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nfs-kernel-server

echo "== 3. Directorios y permisos =="
mkdir -p /srv/nfs/ecopetrol/ensayos
chown root:icpet /srv/nfs/ecopetrol /srv/nfs/ecopetrol/ensayos
chmod 2770 /srv/nfs/ecopetrol /srv/nfs/ecopetrol/ensayos
# Cada home NIS solo lo puede leer su dueño
for h in /home/nis/*/; do
  [[ -d "$h" ]] && chmod 700 "$h"
done

echo "== 4. /etc/exports (root_squash, nunca no_root_squash) =="
for linea in \
  "/srv/nfs/ecopetrol  ${SUBRED}(rw,sync,no_subtree_check,root_squash)" \
  "/home/nis           ${SUBRED}(rw,sync,no_subtree_check,root_squash)"; do
  grep -qF "$linea" /etc/exports 2>/dev/null || echo "$linea" >> /etc/exports
done

echo "== 5. Dominio para idmapd (nombres de usuario) =="
if grep -qE '^[[:space:]]*Domain' /etc/idmapd.conf; then
  sed -i -E "s/^[[:space:]]*Domain.*/Domain = ${NFS_DOMAIN}/" /etc/idmapd.conf
else
  sed -i "/\[General\]/a Domain = ${NFS_DOMAIN}" /etc/idmapd.conf
fi

echo "== 6. Exportar y arrancar =="
exportfs -ra
systemctl enable --now nfs-server
systemctl restart nfs-server

echo "== 7. Comprobación =="
exportfs -v
ss -tlnp | grep ':2049' || true