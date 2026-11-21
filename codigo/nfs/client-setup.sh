#!/usr/bin/env bash
# client-setup.sh: cliente NFSv4 (C, NFS). Requiere NIS en el cliente. Idempotente.
# Uso: sudo ./client-setup.sh .env
set -euo pipefail

ENV_FILE="${1:-.env}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo."; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "No existe $ENV_FILE (copia .env.example)."; exit 1; }
set -a; source "$ENV_FILE"; set +a
: "${SERVER_IP:?falta SERVER_IP}"
: "${NFS_DOMAIN:?falta NFS_DOMAIN}"

echo "== 1. Comprobar que NIS funciona en este cliente =="
getent passwd lab.icpet1 >/dev/null || { echo "Falta NIS en este cliente. Ejecuta client-setup.sh de NIS primero."; exit 1; }

echo "== 2. Instalar nfs-common =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nfs-common

echo "== 3. Dominio para idmapd =="
if grep -qE '^[[:space:]]*Domain' /etc/idmapd.conf; then
  sed -i -E "s/^[[:space:]]*Domain.*/Domain = ${NFS_DOMAIN}/" /etc/idmapd.conf
else
  sed -i "/\[General\]/a Domain = ${NFS_DOMAIN}" /etc/idmapd.conf
fi

echo "== 4. Puntos de montaje =="
mkdir -p /mnt/ecopetrol /home/nis

echo "== 5. /etc/fstab (sin duplicar) =="
add_fstab() { grep -qF "$1" /etc/fstab || echo "$1" >> /etc/fstab; }
add_fstab "${SERVER_IP}:/srv/nfs/ecopetrol  /mnt/ecopetrol  nfs4  defaults,_netdev  0 0"
add_fstab "${SERVER_IP}:/home/nis           /home/nis       nfs4  defaults,_netdev  0 0"

echo "== 6. Montar =="
systemctl daemon-reload
mount -a
findmnt -t nfs4 || true