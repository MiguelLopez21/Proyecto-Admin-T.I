#!/bin/bash
# Entrypoint de Samba. Idempotente: se puede ejecutar en cada arranque.
set -euo pipefail

: "${SMB_GROUP:=administrativa}"
: "${SMB_GID:=3003}"
: "${SMB_USERS:?Falta SMB_USERS (formato usuario:uid,usuario:uid)}"
: "${SMB_PASSWORD:?Falta SMB_PASSWORD}"

SHARE_DIR="/srv/samba/administrativa"

# 1. Grupo (mismo GID que en NIS)
if ! grep -q "^${SMB_GROUP}:" /etc/group; then
  addgroup -g "${SMB_GID}" "${SMB_GROUP}"
  echo "[entrypoint] grupo ${SMB_GROUP} creado (GID ${SMB_GID})"
fi

# 2. Usuarios: sin shell, solo sirven para SMB (mismo UID que en NIS)
IFS=',' read -ra LISTA <<< "${SMB_USERS}"
for par in "${LISTA[@]}"; do
  usuario="${par%%:*}"
  uid="${par##*:}"
  if [ -z "${usuario}" ] || [ -z "${uid}" ] || [ "${usuario}" = "${uid}" ]; then
    echo "[entrypoint] ERROR: entrada invalida en SMB_USERS: '${par}'" >&2
    exit 1
  fi
  if ! id "${usuario}" >/dev/null 2>&1; then
    adduser -D -H -u "${uid}" -G "${SMB_GROUP}" -s /sbin/nologin "${usuario}"
    echo "[entrypoint] usuario ${usuario} creado (UID ${uid})"
  fi
  # smbpasswd -a sirve para crear y para actualizar la clave
  printf '%s\n%s\n' "${SMB_PASSWORD}" "${SMB_PASSWORD}" | smbpasswd -a -s "${usuario}" >/dev/null
done

# 3. Carpeta compartida
mkdir -p "${SHARE_DIR}"
chown root:"${SMB_GROUP}" "${SHARE_DIR}"
chmod 2770 "${SHARE_DIR}"

# 4. Validar la configuracion
if ! testparm -s >/dev/null 2>&1; then
  echo "[entrypoint] ERROR: smb.conf invalido:" >&2
  testparm -s >&2 || true
  exit 1
fi

# 5. smbd en primer plano (Samba 4.19 en Alpine 3.20: --debug-stdout; verificar con smbd --help)
echo "[entrypoint] iniciando smbd"
exec smbd --foreground --no-process-group --debug-stdout
