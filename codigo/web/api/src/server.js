'use strict';
// API del sitio Ecopetrol TI (proyecto académico).
// Al arrancar crea el esquema y carga los datos semilla (idempotente), y luego atiende /api/*.

const fs = require('node:fs');
const path = require('node:path');
const express = require('express');
const { Pool } = require('pg');

const PORT = Number(process.env.PORT || 3000);
const SERVER_IP = process.env.SERVER_IP || '172.20.10.14';
const DOMINIO = process.env.DOMINIO || 'ecopetrol-ti.duckdns.org';
const REINTENTOS = 10;
const ESPERA_MS = 3000;

if (!process.env.DATABASE_URL) {
  console.error('[api] Falta DATABASE_URL (postgresql://usuario:clave@host:5432/base)');
  process.exit(1);
}

// Red interna de Docker: sin SSL.
// Timeouts cortos: si la BD cae, /api/health responde 503 rápido en vez de quedarse colgado.
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 5,
  connectionTimeoutMillis: 3000,
  query_timeout: 5000,
  idleTimeoutMillis: 30000,
});
pool.on('error', (err) => console.error('[db] error en conexión inactiva:', err.message));

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));
const leerSql = (archivo) => fs.readFileSync(path.join(__dirname, '..', 'db', archivo), 'utf8');

async function inicializarBd() {
  for (let intento = 1; intento <= REINTENTOS; intento++) {
    try {
      await pool.query('SELECT 1');
      break;
    } catch (err) {
      console.warn(`[db] intento ${intento}/${REINTENTOS}: la BD no responde (${err.code || err.message})`);
      if (intento === REINTENTOS) throw err;
      await esperar(ESPERA_MS);
    }
  }
  await pool.query(leerSql('schema.sql'));
  await pool.query(leerSql('seed.sql'));
  const { rows } = await pool.query(
    'SELECT (SELECT count(*) FROM sedes) AS sedes, (SELECT count(*) FROM noticias) AS noticias, (SELECT count(*) FROM servicios_ti) AS servicios'
  );
  console.log(`[db] esquema y semilla listos: ${rows[0].sedes} sedes, ${rows[0].noticias} noticias, ${rows[0].servicios} servicios TI`);
}

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', true);

app.use((req, res, next) => {
  const t0 = Date.now();
  res.on('finish', () => console.log(`[http] ${req.method} ${req.originalUrl} ${res.statusCode} ${Date.now() - t0}ms`));
  next();
});

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'ok' });
  } catch (err) {
    res.status(503).json({ status: 'error', db: 'error', detalle: err.code || err.message });
  }
});

app.get('/api/sedes', async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, nombre, ciudad, departamento, tipo, descripcion FROM sedes ORDER BY id'
    );
    res.json(rows);
  } catch (err) { next(err); }
});

app.get('/api/noticias', async (req, res, next) => {
  const limite = Math.min(Math.max(parseInt(req.query.limit, 10) || 10, 1), 50);
  try {
    const { rows } = await pool.query(
      "SELECT id, titulo, resumen, to_char(fecha, 'YYYY-MM-DD') AS fecha, fuente_url FROM noticias ORDER BY fecha DESC, id DESC LIMIT $1",
      [limite]
    );
    res.json(rows);
  } catch (err) { next(err); }
});

app.get('/api/servicios-ti', async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, nombre, protocolo, puerto, como_conectar FROM servicios_ti ORDER BY id'
    );
    const reemplazar = (t) => (t || '').replaceAll('{SERVER_IP}', SERVER_IP).replaceAll('{DOMINIO}', DOMINIO);
    res.json(rows.map((r) => ({ ...r, como_conectar: reemplazar(r.como_conectar) })));
  } catch (err) { next(err); }
});

app.use('/api', (req, res) => res.status(404).json({ error: 'no encontrado' }));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[api] error:', err.message);
  res.status(500).json({ error: 'error interno' });
});

let servidor;
inicializarBd()
  .then(() => {
    servidor = app.listen(PORT, () => console.log(`[api] escuchando en :${PORT} (SERVER_IP=${SERVER_IP}, DOMINIO=${DOMINIO})`));
  })
  .catch((err) => {
    console.error('[api] no se pudo inicializar la BD:', err.message);
    process.exit(1);
  });

function apagar(senal) {
  console.log(`[api] ${senal}: cerrando...`);
  const cerrarPool = () => pool.end().finally(() => process.exit(0));
  if (servidor) servidor.close(cerrarPool); else cerrarPool();
}
process.on('SIGTERM', () => apagar('SIGTERM'));
process.on('SIGINT', () => apagar('SIGINT'));
