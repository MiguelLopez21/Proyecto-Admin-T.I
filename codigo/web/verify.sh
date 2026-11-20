#!/bin/bash
# Uso:
#   bash verify.sh server                      (en el servidor donde corren los contenedores)
#   bash verify.sh client [DOMINIO]            (desde un cliente; por defecto ecopetrol-ti.duckdns.org)
# En "client", si la CA del laboratorio no está instalada en el sistema, pasar su ruta:
#   CA_CERT=/ruta/ca.crt bash verify.sh client
# Solo hace lecturas; no modifica nada.
set -uo pipefail

MODO="${1:-}"
FALLOS=0

ok()   { echo "[OK]    $1"; }
fallo(){ echo "[FALLO] $1"; FALLOS=$((FALLOS+1)); }

DOCKER="docker"
if ! docker ps >/dev/null 2>&1; then DOCKER="sudo docker"; fi

contenedor() {
  $DOCKER ps --filter "label=com.docker.compose.service=$1" --format '{{.Names}}' | head -n1
}

server() {
  local web api salida
  web="$(contenedor ecopetrol-web)"
  api="$(contenedor ecopetrol-api)"
  if [ -n "$web" ]; then ok "contenedor ecopetrol-web corriendo ($web)"; else fallo "no hay contenedor ecopetrol-web"; fi
  if [ -n "$api" ]; then ok "contenedor ecopetrol-api corriendo ($api)"; else fallo "no hay contenedor ecopetrol-api"; fi
  [ -n "$web" ] && [ -n "$api" ] || return

  if $DOCKER exec "$web" nginx -t >/dev/null 2>&1; then ok "nginx -t: configuración válida"; else fallo "nginx -t con errores"; fi

  salida="$($DOCKER exec "$api" wget -qO- http://127.0.0.1:3000/api/health 2>&1)"
  if echo "$salida" | grep -q '"db":"ok"'; then ok "API /api/health: db ok"; else fallo "API /api/health: $salida"; fi

  salida="$($DOCKER exec "$web" wget -qO- http://127.0.0.1/api/sedes 2>&1)"
  if echo "$salida" | grep -q '"nombre"'; then ok "Nginx -> API (/api/sedes) responde"; else fallo "Nginx no llega a la API: $salida"; fi

  if $DOCKER inspect "$web" --format '{{json .NetworkSettings.Networks}}' | grep -q 'dokploy-network'; then
    ok "ecopetrol-web está en dokploy-network (Traefik lo alcanza)"
  else
    fallo "ecopetrol-web no está en dokploy-network"
  fi

  if [ -z "$($DOCKER port "$web" 2>/dev/null)" ]; then ok "la web no publica puertos (entra solo por Traefik)"; else echo "[AVISO] la web publica puertos: $($DOCKER port "$web" | paste -sd' ') (normal solo con docker-compose.dev.yml)"; fi
}

client() {
  local dominio="${2:-ecopetrol-ti.duckdns.org}"
  local url="https://www.$dominio"
  local CURL=(curl -sS --max-time 10)
  [ -n "${CA_CERT:-}" ] && CURL+=(--cacert "$CA_CERT")
  command -v curl >/dev/null || { echo "Instala curl"; exit 2; }

  local codigo
  codigo="$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$url/" 2>/dev/null)"
  if [ "$codigo" = "200" ]; then ok "$url responde 200 con certificado válido (sin -k)"; else fallo "$url respondió '$codigo' (¿CA instalada? ¿DNS?)"; fi

  local salida
  salida="$("${CURL[@]}" "$url/api/health" 2>&1)"
  if echo "$salida" | grep -q '"db":"ok"'; then ok "/api/health: db ok"; else fallo "/api/health: $salida"; fi

  local n
  n="$("${CURL[@]}" "$url/api/sedes" 2>/dev/null | grep -o '"nombre"' | wc -l)"
  if [ "$n" -ge 4 ]; then ok "/api/sedes devuelve $n sedes desde la BD"; else fallo "/api/sedes devuelve $n sedes (se esperaban >= 4)"; fi

  if "${CURL[@]}" -o /dev/null -D - "$url/" 2>/dev/null | grep -qi '^x-content-type-options: nosniff'; then ok "cabeceras de seguridad presentes"; else fallo "falta X-Content-Type-Options"; fi
}

case "$MODO" in
  server) server ;;
  client) client "$@" ;;
  *) echo "Uso: bash verify.sh server | bash verify.sh client [DOMINIO]"; exit 2 ;;
esac

echo
if [ "$FALLOS" -eq 0 ]; then echo "Todas las verificaciones pasaron."; exit 0; else echo "$FALLOS verificacion(es) fallaron."; exit 1; fi
