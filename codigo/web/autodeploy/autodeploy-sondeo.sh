#!/usr/bin/env bash
# Autodeploy por sondeo para Dokploy en una red privada.
#
# Problema: el autodeploy normal de Dokploy espera que GitHub llame al webhook del servidor en cada push,
# pero srv-ecopetrol tiene IP privada (172.20.10.14) y GitHub no lo puede alcanzar.
# Solución: el servidor pregunta a GitHub cada minuto (git ls-remote, conexión de salida). Si la rama cambió,
# llama él mismo al webhook de Dokploy con el mismo formato que usaría GitHub (evento "push").
#
# Configuración: /etc/ecopetrol/autodeploy.env (root, 600). NO se sube al repo porque la URL del webhook
# es un secreto: quien la tenga puede lanzar despliegues.
#   WEBHOOK_URL=https://panel.ecopetrol-ti.duckdns.org/api/deploy/compose/<token>
#   REPO=MiguelLopez21/Proyecto-Admin-T.I
#   BRANCH=main
# Lo ejecuta autodeploy-sondeo.timer cada 60 s. Uso manual: sudo bash autodeploy-sondeo.sh
set -euo pipefail

CONF=/etc/ecopetrol/autodeploy.env
ESTADO_DIR=/var/lib/ecopetrol-autodeploy
# shellcheck source=/dev/null
source "$CONF"
: "${WEBHOOK_URL:?falta WEBHOOK_URL en $CONF}" "${REPO:?falta REPO}" "${BRANCH:=main}"
mkdir -p "$ESTADO_DIR"
ESTADO="$ESTADO_DIR/$(echo "$REPO-$BRANCH" | tr '/' '_')"

remoto="$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" | cut -f1)"
[[ "$remoto" =~ ^[0-9a-f]{40}$ ]] || { echo "No se pudo leer $REPO@$BRANCH (¿sin internet?)" >&2; exit 1; }

anterior="$(cat "$ESTADO" 2>/dev/null || true)"
if [[ -z "$anterior" ]]; then
  echo "$remoto" > "$ESTADO"
  echo "Estado inicial: $BRANCH en ${remoto:0:7}. Se desplegará en el próximo cambio."
  exit 0
fi
[[ "$remoto" == "$anterior" ]] && exit 0

echo "Cambio en $BRANCH: ${anterior:0:7} -> ${remoto:0:7}"

# Cuerpo con el formato del evento push de GitHub. Dokploy usa: ref (rama), after (hash),
# head_commit.message (título del despliegue) y commits[].added/modified/removed (para "Watch Paths").
# El mensaje y los archivos se piden a la API pública de GitHub; si falla, se envía sin ellos.
cuerpo="$(python3 - "$REPO" "$BRANCH" "$anterior" "$remoto" <<'PY'
import json, sys, urllib.request
repo, rama, antes, despues = sys.argv[1:]
mensaje, archivos = "Autodeploy por sondeo", []
try:
    url = f"https://api.github.com/repos/{repo}/compare/{antes}...{despues}"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "autodeploy-sondeo"})
    datos = json.load(urllib.request.urlopen(req, timeout=10))
    if datos.get("commits"):
        mensaje = datos["commits"][-1]["commit"]["message"].splitlines()[0]
    archivos = [f["filename"] for f in datos.get("files", [])]
except Exception as e:
    print(f"(aviso) no se pudo consultar la API de GitHub: {e}", file=sys.stderr)
print(json.dumps({
    "ref": f"refs/heads/{rama}", "before": antes, "after": despues,
    "head_commit": {"id": despues, "message": mensaje},
    "commits": [{"id": despues, "message": mensaje, "added": [], "removed": [], "modified": archivos}],
}))
PY
)"

respuesta="$(curl -sS -m 30 -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" -H "X-GitHub-Event: push" \
  -d "$cuerpo" -w ' HTTP %{http_code}')"
echo "Dokploy: $respuesta"

# Solo se guarda el nuevo hash si Dokploy aceptó; si no, se reintenta en el siguiente minuto.
# 301 = Dokploy decidió no desplegar a propósito (rama distinta o ningún archivo en "Watch Paths").
case "$respuesta" in
  *"HTTP 200"|*"HTTP 301") echo "$remoto" > "$ESTADO" ;;
  *) echo "Dokploy no aceptó el webhook; se reintentará." >&2; exit 1 ;;
esac
