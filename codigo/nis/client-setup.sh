#!/usr/bin/env bash
# client-setup.sh: cliente NIS en Ubuntu 24.04 (C, NIS). Idempotente.
# Uso: sudo ./client-setup.sh .env
set -euo pipefail

ENV_FILE="${1:-.env}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo."; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "No existe $ENV_FILE (copia .env.example)."; exit 1; }
set -a; source "$ENV_FILE"; set +a

echo "== 1. Instalar cliente NIS y SSH (SSH es necesario para la prueba de login) =="
echo "nis nis/domain string $NIS_DOMAIN" | debconf-set-selections
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nis rpcbind openssh-server

echo "== 2. Dominio y servidor NIS =="
echo "$NIS_DOMAIN" > /etc/defaultdomain
domainname "$NIS_DOMAIN"
echo "domain $NIS_DOMAIN server $SERVER_IP" > /etc/yp.conf

echo "== 3. nsswitch: agregar nis (con copia de respaldo, sin duplicar) =="
[[ -f /etc/nsswitch.conf.orig ]] || cp /etc/nsswitch.conf /etc/nsswitch.conf.orig
for k in passwd group shadow netgroup; do
  sed -i -E "/^${k}:/{/[[:space:]]nis([[:space:]]|\$)/!s/\$/ nis/}" /etc/nsswitch.conf
done

echo "== 4. Drop-in de systemd-logind: permitir consultas NIS en el login (Ubuntu 24.04) =="
mkdir -p /etc/systemd/system/systemd-logind.service.d
cat > /etc/systemd/system/systemd-logind.service.d/nis.conf <<FIN
[Service]
IPAddressAllow=any
FIN
systemctl daemon-reload
systemctl restart systemd-logind

echo "== 5. Carpeta para los homes NIS (se montan por NFS en la parte C-NFS) =="
mkdir -p /home/nis

echo "== 6. Servicios =="
systemctl enable --now rpcbind
systemctl enable ypbind
systemctl restart ypbind

echo "== 7. Comprobación =="
ypwhich || true
getent passwd lab.icpet1 || true
id fin.bogota || true
echo
echo "Prueba de login real: ssh lab.icpet1@localhost (pide la contraseña NIS)."