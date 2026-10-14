# renaser-ai-flow · Prototipo funcional

Flujo **registro ficticio → almacenamiento → clasificación → seguimiento → estado actualizado**, construido con n8n, PostgreSQL y Mailpit. Se ejecuta con un solo comando; no requiere cuentas externas.

## Stack

| Servicio | URL local | Propósito |
|---|---|---|
| **n8n** | http://localhost:5678 | Editor de flujos y webhooks |
| **Mailpit** | http://localhost:8025 | Bandeja SMTP local (todos los correos llegan aquí) |
| **PostgreSQL** | `localhost:5433` (base `crm`) | Mini-CRM: tabla `leads` + historial de etapas |

## Requisitos

- Docker + Docker Compose v2

## Cómo ejecutar

```bash
# 1. Clonar el repo
git clone <URL> renaser-ia-flow && cd renaser-ia-flow

# 2. Levantar todo
docker compose up -d

# 3. Abrir el editor (primera vez pedirá crear cuenta de propietario)
open http://localhost:5678

# 4. Ver la bandeja de correos
open http://localhost:8025
```

El servicio `n8n-import` importa credenciales y flujos automáticamente antes de que n8n arranque. Los flujos quedan publicados (activos) desde el primer boot.

## Prueba de punta a punta

```bash
# Envía 3 leads ficticios, verifica el CRM, los correos, la confirmación y la no-duplicación
./scripts/prueba_e2e.sh
```

El script no requiere navegador: usa `curl`, `psql` y la API de Mailpit.

---

## Nodo por nodo · Flujo 01: Registro y seguimiento

```
Formulario → Clasificar lead → Guardar lead (upsert) → ¿Ya confirmado?
                                                             ├─ Sí → Sin reenvío
                                                             └─ No → Armar correo → Enviar correo → Actualizar etapa: Contactado
```

### 1. Formulario de registro (`n8n-nodes-base.formTrigger` v2.3)
- Genera un formulario web real en `/form/registro`.
- Campos: nombre, email, teléfono, interés (dropdown), disponibilidad (dropdown), canal (dropdown).
- Configuración clave: `responseMode: onReceived` (no bloquea el flujo), `path: registro`.

### 2. Clasificar lead (`n8n-nodes-base.code` v2)
- Mapea las claves posicionales `field-0…field-5` que produce el Form Trigger a nombres semánticos.
- Calcula el puntaje:

| Campo | Alto / Sí / Referido | Medio / Tal vez / WhatsApp | Bajo / No / Formulario web | Redes sociales |
|---|---|---|---|---|
| Interés | 40 | 20 | 5 | — |
| Disponibilidad | 40 | 15 | 0 | — |
| Canal | 20 | 15 | 10 | 5 |

- **≥ 70 → Caliente · 40–69 → Tibio · < 40 → Frío**

### 3. Guardar lead — upsert (`n8n-nodes-base.postgres` v2.6)
- `INSERT … ON CONFLICT (email) DO UPDATE`: nunca duplica un email.
- Si el lead ya existía, actualiza datos y reclasifica, pero **no toca la etapa** (no puede retroceder).
- Devuelve `id`, `token` (UUID opaco), `etapa` y `clasificacion`.

### 4. ¿Ya confirmado? (`n8n-nodes-base.if` v2.2)
- Si la etapa es `Confirmado`, `Asistió` o `No_asistió`: rama `true` → no se reenvía el correo.
- Si sigue en `Nuevo` o `Contactado`: rama `false` → continúa.

### 5. Armar correo según clasificación (`n8n-nodes-base.code` v2)
- Genera asunto y HTML diferentes según la clasificación:
  - **Caliente**: «Tu lugar está reservado» + botón «Confirmo mi asistencia».
  - **Tibio**: «Esto es lo que vivirás» + botón.
  - **Frío**: mensaje de nutrición, sin botón.
- El botón apunta a `http://localhost:5678/webhook/confirmar?token=<UUID>`.

### 6. Enviar correo de seguimiento (`n8n-nodes-base.emailSend` v2.1)
- SMTP → Mailpit (puerto 1025). Credencial: `SMTP Mailpit (local)`.
- En producción se cambia el host/puerto a WhatsApp API o a un proveedor SMTP real.

### 7. Actualizar etapa: Contactado (`n8n-nodes-base.postgres` v2.6)
- `UPDATE leads SET etapa='Contactado', fecha_contacto=now() WHERE id=$1 AND etapa='Nuevo'`.
- Inserta una fila en `historial_etapas` con `origen='flujo_01:correo_enviado'`.

---

## Nodo por nodo · Flujo 02: Confirmación de asistencia

```
Clic en «Confirmo asistencia» (Webhook) → Actualizar etapa: Confirmado → ¿Se confirmó?
                                                                               ├─ Sí → Página: confirmado ✅
                                                                               └─ No → Página: inválido o ya confirmado ⚠️
```

### 1. Clic en «Confirmo asistencia» (`n8n-nodes-base.webhook` v2.1)
- `GET /webhook/confirmar?token=<UUID>`.
- `responseMode: responseNode` (delega la respuesta al nodo `Respond to Webhook`).

### 2. Actualizar etapa: Confirmado (`n8n-nodes-base.postgres` v2.6)
- Busca el lead por `token::text` (comparación segura).
- `UPDATE … SET etapa='Confirmado' WHERE token=$1 AND etapa IN ('Nuevo','Contactado')`.
- Idempotente: si el token ya fue usado o no existe, `actualizado=0`.

### 3. ¿Se confirmó? (`n8n-nodes-base.if` v2.2)
- `actualizado > 0` → `true`.

### 4a. Página: confirmado (`n8n-nodes-base.respondToWebhook` v1.4)
- Devuelve HTML con `Content-Type: text/html` y mensaje de éxito.

### 4b. Página: inválido o ya confirmado (`n8n-nodes-base.respondToWebhook` v1.4)
- Detecta si el token existía pero ya estaba avanzado (`etapa_previa` presente) o si el token era inválido.

---

## Modelo de datos

```sql
-- Un registro por persona (email UNIQUE = sin duplicados)
leads (id, nombre, email, telefono, interes, disponibilidad, canal,
       puntaje, clasificacion, etapa, token UUID, fecha_contacto,
       fecha_confirmacion, created_at, updated_at)

-- Trazabilidad: cada cambio de etapa queda registrado
historial_etapas (id, lead_id → leads, etapa_anterior, etapa_nueva, origen, fecha)

-- Vista del embudo (KPI básico)
embudo: SELECT etapa, clasificacion, COUNT(*) FROM leads GROUP BY ...
```

## Flujos en el repo

- [`n8n/workflows/01_registro_seguimiento.json`](./n8n/workflows/01_registro_seguimiento.json)
- [`n8n/workflows/02_confirmacion_asistencia.json`](./n8n/workflows/02_confirmacion_asistencia.json)

Exportación limpia: sin ejecuciones ni datos de prueba.

## Cómo detener y limpiar

```bash
docker compose down          # detiene, conserva datos
docker compose down -v       # detiene y borra volúmenes (reset completo)
```