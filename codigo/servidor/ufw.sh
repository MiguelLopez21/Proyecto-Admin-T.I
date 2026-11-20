#!/usr/bin/env bash
# Cortafuegos de srv-ecopetrol (punto extra del rol A).
#
# Problema que resuelve: Docker publica los puertos de los contenedores (Traefik 80/443, Dokploy 3000,
# NTP 123/udp, Samba 445, CUPS 631...) con reglas propias en la cadena FORWARD, ANTES de que UFW las vea.
# Por eso "ufw deny 3000" no sirve de nada. Este script hace dos cosas:
#   1. UFW (cadena INPUT): política deny entrante; solo SSH y los puertos del anfitrión de la lista.
#      Aplica a sshd y a contenedores con network_mode: host.
#   2. Cadena DOCKER-USER (la que Docker reserva para el administrador y consulta primero): el tráfico
#      que entra por la interfaz de la LAN hacia un contenedor solo pasa si viene de las subredes permitidas.
#      El tráfico entre contenedores y la salida a internet de los contenedores no se tocan.
#
# Uso:
#   sudo bash ufw.sh                       # aplica (idempotente)
#   sudo SUBREDES="172.20.10.0/28 192.168.1.0/24" bash ufw.sh   # agregar la red de casa para pruebas
#   sudo bash ufw.sh --quitar              # revierte todo (ufw disable + borra el bloque DOCKER-USER)
#   sudo bash ufw.sh --estado              # muestra reglas de UFW y de DOCKER-USER
#
# Variables:
#   SUBREDES      subredes que pueden usar los servicios (por defecto la del hotspot de la demo, una /28)
#   PUERTOS_HOST  puertos del anfitrión abiertos a SUBREDES (además de 22/tcp). Cuando C entregue NIS/NFS,
#                 si corren con network_mode: host, agregar aquí sus puertos (ej. "111 2049/tcp").
#   IFACE         interfaz de la LAN (por defecto la de la ruta por defecto)
#
# Seguridad: si se ejecuta por SSH, la IP del cliente actual siempre queda permitida en 22/tcp,
# para no perder la sesión aunque esa IP no esté en SUBREDES.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)" >&2; exit 1; }

SUBREDES="${SUBREDES:-172.20.10.0/28}"
PUERTOS_HOST="${PUERTOS_HOST:-}"
IFACE="${IFACE:-$(ip -4 route show default | awk '{print $5; exit}')}"
AFTER=/etc/ufw/after.rules
INICIO="# BEGIN ecopetrol DOCKER-USER (generado por codigo/servidor/ufw.sh)"
FIN="# END ecopetrol DOCKER-USER"

log() { echo "[ufw] $*"; }

quitar_bloque() {
  # Borra el bloque anterior de after.rules (si existe) para poder reescribirlo
  sed -i "/^${INICIO//\//\\/}\$/,/^${FIN//\//\\/}\$/d" "$AFTER"
}

estado() {
  ufw status verbose
  echo "--- DOCKER-USER"
  iptables -S DOCKER-USER 2>/dev/null || echo "(la cadena no existe: ¿Docker no ha arrancado?)"
}

case "${1:-}" in
  --estado) estado; exit 0 ;;
  --quitar)
    ufw --force disable
    quitar_bloque
    iptables -F DOCKER-USER 2>/dev/null && iptables -A DOCKER-USER -j RETURN || true
    log "UFW desactivado y DOCKER-USER vacía (como la deja Docker)."
    exit 0 ;;
  "") ;;
  *) echo "Opción desconocida: $1 (usar --estado o --quitar)" >&2; exit 2 ;;
esac

[[ -n "$IFACE" ]] || { echo "No se encontró la interfaz de la LAN; pasar IFACE=..." >&2; exit 1; }
command -v ufw >/dev/null || { apt-get update -q && apt-get install -yq ufw; }
log "Interfaz LAN: $IFACE · Subredes permitidas: $SUBREDES"

# --- 1. UFW (INPUT): se reinicia para que el script sea la única fuente de las reglas
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw default allow routed   # el filtrado del tráfico hacia contenedores lo hace DOCKER-USER, no UFW

for red in $SUBREDES; do
  ufw allow from "$red" to any port 22 proto tcp comment 'SSH administracion'
  for p in $PUERTOS_HOST; do
    if [[ $p == */* ]]; then ufw allow from "$red" to any port "${p%/*}" proto "${p#*/}" comment 'servicio host'
    else ufw allow from "$red" to any port "$p" comment 'servicio host'; fi
  done
done

# sudo borra SSH_CLIENT, así que se leen las sesiones SSH establecidas en este momento
for cliente_ssh in $(ss -Htn state established '( sport = :22 )' | awk '{print $4}' | sed 's/:[0-9]*$//' | sort -u); do
  [[ "$cliente_ssh" =~ ^[0-9.]+$ ]] || continue
  ufw allow from "$cliente_ssh" to any port 22 proto tcp comment 'SSH sesion actual'
  log "SSH permitido también para la sesión actual: $cliente_ssh"
done

# --- 2. DOCKER-USER (FORWARD): se escribe en after.rules para que sobreviva reinicios y 'ufw reload'
quitar_bloque
{
  echo "$INICIO"
  echo "*filter"
  echo ":DOCKER-USER - [0:0]"
  echo "-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN"
  echo "-A DOCKER-USER ! -i $IFACE -j RETURN"
  for red in $SUBREDES; do echo "-A DOCKER-USER -s $red -j RETURN"; done
  echo "-A DOCKER-USER -m limit --limit 3/min -j LOG --log-prefix \"[DOCKER-USER BLOQUEADO] \""
  echo "-A DOCKER-USER -j DROP"
  echo "COMMIT"
  echo "$FIN"
} >> "$AFTER"

ufw --force enable >/dev/null
ufw reload >/dev/null
log "Listo."
estado
