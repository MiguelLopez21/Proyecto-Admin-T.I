#!/usr/bin/env bash
# Genera una CA propia y, firmado por ella, el certificado del servidor para Traefik/Dokploy.
#
# Uso:   bash generar-certificado.sh <DOMINIO> <SERVER_IP> [directorio_salida]
# Ej.:   bash generar-certificado.sh ecopetrol-ti.duckdns.org 172.20.10.14 ~/certs
#
# Salida (en el directorio indicado, por defecto ./certs):
#   ca.key / ca.crt                  CA propia (ca.crt se importa en los clientes)
#   servidor.key / servidor.crt      certificado del servidor (SAN: DOMINIO, *.DOMINIO, IP)
#   fullchain.crt                    servidor.crt + ca.crt  -> se pega en Dokploy (Certificate Data)
#
# Las claves (*.key) NUNCA se suben al repositorio (.gitignore).
# Si la CA ya existe se reutiliza, para no tener que reimportarla en los clientes.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <DOMINIO> <SERVER_IP> [directorio_salida]" >&2
  exit 1
fi

DOMINIO="$1"
SERVER_IP="$2"
OUT="${3:-./certs}"
DIAS_CA=3650      # 10 años para la CA del laboratorio
DIAS_SRV=397      # máximo que aceptan los navegadores para un certificado de servidor

command -v openssl >/dev/null || { echo "Falta openssl" >&2; exit 1; }
mkdir -p "$OUT"
chmod 700 "$OUT"
cd "$OUT"
umask 077

log() { echo "[certificado] $*"; }

# 1. CA propia (ECDSA P-256)
if [[ -f ca.key && -f ca.crt ]]; then
  log "CA existente reutilizada: $(openssl x509 -in ca.crt -noout -subject)"
else
  log "Creando CA propia..."
  openssl ecparam -name prime256v1 -genkey -noout -out ca.key
  openssl req -x509 -new -key ca.key -sha256 -days "$DIAS_CA" \
    -subj "/C=CO/O=Ecopetrol TI (laboratorio)/CN=Ecopetrol TI Lab CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash" \
    -out ca.crt
fi

# 2. Clave y CSR del servidor
log "Creando clave y solicitud del servidor para $DOMINIO / $SERVER_IP..."
openssl ecparam -name prime256v1 -genkey -noout -out servidor.key
openssl req -new -key servidor.key -sha256 \
  -subj "/C=CO/O=Ecopetrol TI (laboratorio)/CN=$DOMINIO" \
  -out servidor.csr

# 3. Firma con la CA, con SAN y extensiones de servidor TLS
cat > servidor.ext <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:$DOMINIO,DNS:*.$DOMINIO,IP:$SERVER_IP
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
openssl x509 -req -in servidor.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -sha256 -days "$DIAS_SRV" -extfile servidor.ext -out servidor.crt

cat servidor.crt ca.crt > fullchain.crt
rm -f servidor.csr servidor.ext
chmod 644 ca.crt servidor.crt fullchain.crt

# 4. Comprobaciones
log "Verificando la cadena..."
openssl verify -CAfile ca.crt servidor.crt
openssl x509 -in servidor.crt -noout -subject -issuer -dates -ext subjectAltName
log "Listo. Archivos en $(pwd):"
ls -l
