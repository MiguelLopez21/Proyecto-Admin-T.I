#!/usr/bin/env bash
# Preparación base de srv-ecopetrol (Ubuntu Server 24.04), después de instalar el SO.
# Idempotente: se puede correr varias veces.
#   - actualiza el sistema
#   - crea swap de 2 GB (/swapfile)
#   - zona horaria America/Bogota
#   - DESACTIVA el cliente NTP del host: la única autoridad de hora será el contenedor chrony (B),
#     que tiene SYS_TIME; dos procesos ajustando el reloj se pelean.
# Uso: sudo bash preparar-servidor.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)" >&2; exit 1; }
log() { echo "[preparar] $*"; }

log "1/4 Actualizando paquetes..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get full-upgrade -yq

log "2/4 Swap de 2 GB..."
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  [[ -f /swapfile ]] || fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

log "3/4 Zona horaria America/Bogota..."
timedatectl set-timezone America/Bogota

log "4/4 Desactivando NTP del host (lo hará el contenedor chrony)..."
timedatectl set-ntp false

log "Resultado:"
free -h
timedatectl | grep -E 'Time zone|NTP service|System clock'
[[ -f /var/run/reboot-required ]] && log "AVISO: se requiere reiniciar (sudo reboot)." || true
