#!/bin/sh
# =============================================================
# Importa credenciales y flujos en n8n y los activa.
# Estrategia para single-node (sin multi-main):
#   1. import:credentials  →  guarda credenciales cifradas en la DB
#   2. import:workflow     →  crea los flujos (quedan inactivos)
#   3. publish:workflow    →  los marca como publicados/activos en la DB
#      (n8n los cargará activos la primera vez que arranque)
#
# El marcador evita reimportar si el volumen ya fue inicializado.
# =============================================================
set -e

MARKER=/home/node/.n8n/.renaser_importado

if [ -f "$MARKER" ]; then
  echo "[import] Ya importado anteriormente. Nada que hacer."
  exit 0
fi

echo "[import] Importando credenciales..."
n8n import:credentials --input=/import/credentials/credentials.json

echo "[import] Importando flujos..."
n8n import:workflow --separate --input=/import/workflows

echo "[import] Publicando flujo 01..."
n8n publish:workflow --id=renaserFlujo0001

echo "[import] Publicando flujo 02..."
n8n publish:workflow --id=renaserFlujo0002

touch "$MARKER"
echo "[import] Listo. n8n levantará con los flujos publicados (activos)."
