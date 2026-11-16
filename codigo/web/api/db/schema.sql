-- Esquema del sitio Ecopetrol TI. Idempotente: se ejecuta en cada arranque de la API.

CREATE TABLE IF NOT EXISTS sedes (
  id           SERIAL PRIMARY KEY,
  nombre       TEXT UNIQUE NOT NULL,
  ciudad       TEXT,
  departamento TEXT,
  tipo         TEXT CHECK (tipo IN ('corporativa', 'refinería', 'instituto', 'filial')),
  descripcion  TEXT
);

CREATE TABLE IF NOT EXISTS noticias (
  id         SERIAL PRIMARY KEY,
  titulo     TEXT UNIQUE NOT NULL,
  resumen    TEXT,
  fecha      DATE,
  fuente_url TEXT
);

CREATE TABLE IF NOT EXISTS servicios_ti (
  id            SERIAL PRIMARY KEY,
  nombre        TEXT UNIQUE NOT NULL,
  protocolo     TEXT,
  puerto        TEXT,
  como_conectar TEXT
);

CREATE INDEX IF NOT EXISTS noticias_fecha_idx ON noticias (fecha DESC);
