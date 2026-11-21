#!/usr/bin/env bash
# install.sh: servidor NIS maestro (C, NIS). Idempotente.
# Uso: sudo ./install.sh .env
set -euo pipefail

ENV_FILE="${1:-.env}"
DIR="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo."; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "No existe $ENV_FILE (copia .env.example)."; exit 1; }
set -a; source "$ENV_FILE"; set +a
: "${NIS_DOMAIN:?falta NIS_DOMAIN}"
: "${SERVER_IP:?falta SERVER_IP}"
: "${SUBRED_NET:?falta SUBRED_NET}"
: "${SUBRED_MASK:?falta SUBRED_MASK}"
: "${DEMO_PASSWORD:?falta DEMO_PASSWORD}"

echo "== 1. Dominio NIS =="
echo "$NIS_DOMAIN" > /etc/defaultdomain
domainname "$NIS_DOMAIN"

echo "== 2. Instalar nis y rpcbind (sin preguntas) =="
echo "nis nis/domain string $NIS_DOMAIN" | debconf-set-selections
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nis rpcbind

echo "== 3. Grupos y usuarios desde los CSV =="
mkdir -p /home/nis && chmod 0755 /home/nis

tail -n +2 "$DIR/config/grupos.csv" | tr -d '\r' | while IFS=, read -r grupo gid; do
  [[ -z "$grupo" ]] && continue
  getent group "$grupo" >/dev/null || groupadd -g "$gid" "$grupo"
done

tail -n +2 "$DIR/config/usuarios.csv" | tr -d '\r' | while IFS=, read -r usuario uid grupo extras nombre; do
  [[ -z "$usuario" ]] && continue
  if ! getent passwd "$usuario" >/dev/null; then
    args=(-u "$uid" -g "$grupo" -m -d "/home/nis/$usuario" -s /bin/bash -c "$nombre")
    [[ -n "$extras" ]] && args+=(-G "$extras")
    useradd "${args[@]}"
    # La contraseña solo se fija al crear la cuenta, para no pisar cambios posteriores
    echo "$usuario:$DEMO_PASSWORD" | chpasswd
  fi
done

echo "== 4. /etc/default/nis (puertos fijos) =="
[[ -f /etc/default/nis.orig ]] || cp /etc/default/nis /etc/default/nis.orig
cat > /etc/default/nis <<FIN
NISSERVER=master
NISCLIENT=false
YPPWDDIR=/etc
YPSERVARGS="-p 834"
YPPASSWDDARGS="--port 835"
FIN

echo "== 5. securenets: solo localhost y la subred del laboratorio =="
cat > /etc/ypserv.securenets <<FIN
# Gestionado por install.sh (C, NIS). No abrir a 0.0.0.0.
255.0.0.0      127.0.0.0
${SUBRED_MASK}  ${SUBRED_NET}
FIN

echo "== 6. Makefile de mapas: solo UID/GID >= 1000 y fusionar passwd/group =="
MK=/var/yp/Makefile
sed -i -E \
  -e 's/^#?[[:space:]]*MINUID[[:space:]]*=.*/MINUID=1000/' \
  -e 's/^#?[[:space:]]*MINGID[[:space:]]*=.*/MINGID=1000/' \
  -e 's/^#?[[:space:]]*MERGE_PASSWD[[:space:]]*=.*/MERGE_PASSWD=true/' \
  -e 's/^#?[[:space:]]*MERGE_GROUP[[:space:]]*=.*/MERGE_GROUP=true/' "$MK"

echo "== 7. Servicios =="
systemctl enable --now rpcbind
systemctl enable ypserv yppasswdd
systemctl restart ypserv yppasswdd

echo "== 8. Mapas NIS =="
if [[ -d "/var/yp/$NIS_DOMAIN" ]]; then
  make -C /var/yp
else
  /usr/lib/yp/ypinit -m < /dev/null
fi

echo "== 9. Comprobación =="
rpcinfo -p localhost | grep -E 'ypserv|yppasswdd' || true
ypcat -d "$NIS_DOMAIN" -h localhost passwd
echo
echo "Listo. Cada vez que crees o cambies un usuario aquí, ejecuta: sudo make -C /var/yp"