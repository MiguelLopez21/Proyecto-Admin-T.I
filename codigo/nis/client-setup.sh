#!/usr/bin/env bash
# client-setup.sh: cliente NIS en Ubuntu 24.04 (C, NIS). Idempotente.
# Uso: sudo ./client-setup.sh .env
set -euo pipefail

ENV_FILE="${1:-.env}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo."; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "No existe $ENV_FILE (copia .env.example)."; exit 1; }
set -a; source <(tr -d '\r' < "$ENV_FILE"); set +a   # tolera un .env guardado con CRLF (Windows)
: "${NIS_DOMAIN:?falta NIS_DOMAIN}"
: "${SERVER_IP:?falta SERVER_IP}"

echo "== 1. Instalar cliente NIS y SSH (SSH es necesario para la prueba de login) =="
# Al arrancar, unattended-upgrades puede tener tomados dpkg y debconf: esperar (máx. 10 min)
for i in $(seq 1 120); do
  fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/debconf/config.dat >/dev/null 2>&1 || break
  [[ $i -eq 120 ]] && { echo "apt/debconf siguen ocupados tras 10 min."; exit 1; }
  [[ $i -eq 1 ]] && echo "Esperando a que termine otra instalación (unattended-upgrades)..."
  sleep 5
done
echo "nis nis/domain string $NIS_DOMAIN" | debconf-set-selections
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=600 update -y
apt-get -o DPkg::Lock::Timeout=600 install -y nis rpcbind openssh-server

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

echo "== 7. nscd: sin caché de grupos (rompe los grupos secundarios de NIS) =="
# El paquete nis instala nscd como dependencia. Con su caché de grupos activa, "id admin.ti" solo muestra
# el grupo principal (falta icpet/administrativa) y NFS niega el acceso. Se deja la caché de passwd.
if [[ -f /etc/nscd.conf ]]; then
  [[ -f /etc/nscd.conf.orig ]] || cp /etc/nscd.conf /etc/nscd.conf.orig
  sed -i -E 's/^([[:space:]]*enable-cache[[:space:]]+group[[:space:]]+)yes/\1no/' /etc/nscd.conf
  systemctl restart nscd
fi

echo "== 8. Comprobación =="
ypwhich || true
getent passwd lab.icpet1 | cut -d: -f1,3- || true   # sin el hash de la contraseña
id fin.bogota || true
id admin.ti || true
echo
echo "Prueba de login real: ssh lab.icpet1@localhost (pide la contraseña NIS)."
