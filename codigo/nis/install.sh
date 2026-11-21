#!/usr/bin/env bash
# install.sh: servidor NIS maestro (C, NIS). Idempotente.
# Uso: sudo ./install.sh .env
set -euo pipefail

ENV_FILE="${1:-.env}"
DIR="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo."; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "No existe $ENV_FILE (copia .env.example)."; exit 1; }
set -a; source <(tr -d '\r' < "$ENV_FILE"); set +a   # tolera un .env guardado con CRLF (Windows)
: "${NIS_DOMAIN:?falta NIS_DOMAIN}"
: "${SERVER_IP:?falta SERVER_IP}"
: "${SUBRED_NET:?falta SUBRED_NET}"
: "${SUBRED_MASK:?falta SUBRED_MASK}"
: "${DEMO_PASSWORD:?falta DEMO_PASSWORD}"

echo "== 1. Dominio NIS =="
echo "$NIS_DOMAIN" > /etc/defaultdomain
domainname "$NIS_DOMAIN"

echo "== 2. Instalar nis y rpcbind (sin preguntas) =="
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
apt-get -o DPkg::Lock::Timeout=600 install -y nis rpcbind

echo "== 3. Grupos y usuarios desde los CSV =="
mkdir -p /home/nis && chmod 0755 /home/nis

[[ -f "$DIR/config/grupos.csv" && -f "$DIR/config/usuarios.csv" ]] \
  || { echo "Faltan config/grupos.csv o config/usuarios.csv junto a este script."; exit 1; }

tail -n +2 "$DIR/config/grupos.csv" | tr -d '\r' | while IFS=, read -r grupo gid; do
  [[ -z "$grupo" ]] && continue
  if actual="$(getent group "$grupo")"; then
    [[ "$(cut -d: -f3 <<<"$actual")" == "$gid" ]] \
      || { echo "El grupo $grupo ya existe con otro GID (se esperaba $gid). Corrígelo a mano."; exit 1; }
  else
    groupadd -g "$gid" "$grupo"
  fi
done

# grupos_extra va separado por ';' dentro del CSV (la coma separa columnas)
tail -n +2 "$DIR/config/usuarios.csv" | tr -d '\r' | while IFS=, read -r usuario uid grupo extras nombre; do
  [[ -z "$usuario" ]] && continue
  extras="${extras//;/,}"
  if actual="$(getent passwd "$usuario")"; then
    [[ "$(cut -d: -f3 <<<"$actual")" == "$uid" ]] \
      || { echo "El usuario $usuario ya existe con otro UID (se esperaba $uid). Corrígelo a mano."; exit 1; }
    # Ya existe: solo asegura los grupos extra (no toca la contraseña)
    # (con "if" y no con "&&": si extras está vacío, "&&" devolvería 1 y set -e cortaría el script)
    if [[ -n "$extras" ]]; then usermod -aG "$extras" "$usuario"; fi
  else
    args=(-u "$uid" -g "$grupo" -m -d "/home/nis/$usuario" -s /bin/bash -c "$nombre")
    [[ -n "$extras" ]] && args+=(-G "$extras")
    useradd "${args[@]}" "$usuario"
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

echo "== 6. Makefile de mapas: solo UID/GID >= 2000 y fusionar passwd/group =="
# 2000 y no 1000: con 1000 se exportaría 'sysadmin' (UID 1000, admin del servidor) con su hash
# a toda la red, y chocaría con el usuario local UID 1000 de cada cliente.
MK=/var/yp/Makefile
sed -i -E \
  -e 's/^#?[[:space:]]*MINUID[[:space:]]*=.*/MINUID=2000/' \
  -e 's/^#?[[:space:]]*MINGID[[:space:]]*=.*/MINGID=2000/' \
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
# Sin la columna 2 (hash de la contraseña) para no exponerlo en pantalla ni en capturas
ypcat -d "$NIS_DOMAIN" -h localhost passwd | cut -d: -f1,3-
echo
echo "Listo. Cada vez que crees o cambies un usuario aquí, ejecuta: sudo make -C /var/yp"
