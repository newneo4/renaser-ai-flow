-- =============================================================
-- Mini-CRM del prototipo renaser-ai-flow
-- Se ejecuta automáticamente en el primer arranque de Postgres.
-- =============================================================

-- Tabla principal: un registro por persona (email único = sin duplicados)
CREATE TABLE IF NOT EXISTS leads (
    id                  SERIAL PRIMARY KEY,
    nombre              TEXT        NOT NULL,
    email               TEXT        NOT NULL UNIQUE,
    telefono            TEXT,
    interes             TEXT        NOT NULL CHECK (interes IN ('Alto', 'Medio', 'Bajo')),
    disponibilidad      TEXT        NOT NULL CHECK (disponibilidad IN ('Sí', 'Tal vez', 'No')),
    canal               TEXT        NOT NULL CHECK (canal IN ('Referido', 'WhatsApp', 'Formulario web', 'Redes sociales')),
    puntaje             INTEGER     NOT NULL,
    clasificacion       TEXT        NOT NULL CHECK (clasificacion IN ('Caliente', 'Tibio', 'Frío')),
    -- Embudo definido en la arquitectura: Nuevo → Contactado → Confirmado → Asistió / No_asistió
    etapa               TEXT        NOT NULL DEFAULT 'Nuevo'
                                    CHECK (etapa IN ('Nuevo', 'Contactado', 'Confirmado', 'Asistió', 'No_asistió')),
    -- Token opaco para el enlace de confirmación (no se expone el id interno)
    token               UUID        NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    fecha_contacto      TIMESTAMPTZ,
    fecha_confirmacion  TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Historial de cambios de etapa: permite medir conversión por etapa (KPIs)
CREATE TABLE IF NOT EXISTS historial_etapas (
    id              SERIAL PRIMARY KEY,
    lead_id         INTEGER     NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    etapa_anterior  TEXT,
    etapa_nueva     TEXT        NOT NULL,
    origen          TEXT        NOT NULL,   -- qué flujo/nodo provocó el cambio
    fecha           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_leads_etapa ON leads (etapa);
CREATE INDEX IF NOT EXISTS idx_historial_lead ON historial_etapas (lead_id);

-- Vista rápida del embudo (cuántos leads hay en cada etapa y clasificación)
CREATE OR REPLACE VIEW embudo AS
SELECT etapa, clasificacion, COUNT(*) AS total
FROM leads
GROUP BY etapa, clasificacion
ORDER BY etapa, clasificacion;
