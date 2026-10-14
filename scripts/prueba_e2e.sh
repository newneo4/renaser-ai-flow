#!/usr/bin/env bash
# =============================================================
# Prueba de punta a punta del prototipo (sin navegador).
#   1) Envía 3 registros ficticios al formulario (Caliente/Tibio/Frío)
#   2) Verifica clasificación y etapa en Postgres
#   3) Verifica los correos en Mailpit
#   4) "Hace clic" en el enlace de confirmación del lead Caliente
#   5) Reenvía el mismo email para comprobar que no se duplica ni retrocede
# Uso: ./scripts/prueba_e2e.sh
# =============================================================
set -euo pipefail

N8N=${N8N:-http://localhost:5678}
MAILPIT=${MAILPIT:-http://localhost:8025}
SUFIJO=$(date +%s)
psql_crm() { docker exec -i renaser-postgres psql -U crm -d crm -At -F ' | ' -c "$1"; }

enviar() { # nombre email telefono interes disponibilidad canal
  curl -s -o /dev/null -w "  → %{http_code} $2\n" -X POST "$N8N/form/registro" \
    -F "field-0=$1" \
    -F "field-1=$2" \
    -F "field-2=$3" \
    -F "field-3=$4" \
    -F "field-4=$5" \
    -F "field-5=$6"
}

echo "1) Enviando registros ficticios al formulario..."
enviar "Ana Caliente"  "ana.$SUFIJO@demo.test"   "+51 900 000 001" "Alto"  "Sí"      "Referido"
enviar "Beto Tibio"    "beto.$SUFIJO@demo.test"  "+51 900 000 002" "Medio" "Tal vez" "WhatsApp"
enviar "Carla Fría"    "carla.$SUFIJO@demo.test" "+51 900 000 003" "Bajo"  "No"      "Redes sociales"
sleep 3

echo; echo "2) Leads en el CRM (Postgres):"
psql_crm "SELECT nombre, puntaje, clasificacion, etapa FROM leads WHERE email LIKE '%.$SUFIJO@demo.test' ORDER BY id;"

echo; echo "3) Correos en Mailpit:"
curl -s "$MAILPIT/api/v1/search?query=$SUFIJO" \
  | python3 -c 'import json,sys; [print("  ✉", m["To"][0]["Address"], "|", m["Subject"]) for m in json.load(sys.stdin)["messages"]]'

echo; echo "4) Clic en «Confirmo mi asistencia» (lead Caliente)..."
TOKEN=$(psql_crm "SELECT token FROM leads WHERE email='ana.$SUFIJO@demo.test';")
curl -s "$N8N/webhook/confirmar?token=$TOKEN" | grep -o '<h1[^>]*>[^<]*</h1>' | sed 's/<[^>]*>//g; s/^/  Página: /'
echo "  Segundo clic:"
curl -s "$N8N/webhook/confirmar?token=$TOKEN" | grep -o '<h1[^>]*>[^<]*</h1>' | sed 's/<[^>]*>//g; s/^/  Página: /'
echo "  Token inválido:"
curl -s "$N8N/webhook/confirmar?token=no-existe" | grep -o '<h1[^>]*>[^<]*</h1>' | sed 's/<[^>]*>//g; s/^/  Página: /'

echo; echo "5) Re-registro del lead confirmado (no debe duplicar ni retroceder):"
enviar "Ana Caliente" "ana.$SUFIJO@demo.test" "+51 900 000 001" "Medio" "Sí" "Referido"
sleep 2
psql_crm "SELECT count(*) AS registros, max(etapa) AS etapa, max(clasificacion) AS clasif FROM leads WHERE email='ana.$SUFIJO@demo.test';"

echo; echo "Historial de etapas:"
psql_crm "SELECT l.nombre, h.etapa_anterior, h.etapa_nueva, h.origen FROM historial_etapas h JOIN leads l ON l.id=h.lead_id WHERE l.email LIKE '%.$SUFIJO@demo.test' ORDER BY h.id;"

echo; echo "Embudo actual:"
psql_crm "SELECT * FROM embudo;"
