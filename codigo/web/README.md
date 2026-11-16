# Web + API + Base de datos: portal "Ecopetrol TI"

## 1. Servicio y responsable

Sitio web interno de la sede Bogotá: información de la compañía (quiénes somos, sedes, noticias con su fuente) y un **Portal TI del empleado** que explica cómo conectarse a la carpeta compartida, la impresora, el NTP, el NFS y el NIS. Las sedes, las noticias y los servicios se leen de **PostgreSQL** a través de una API. Ver la justificación en [`analisis.md`](../../analisis.md).

Responsable: B (Web, BD y NTP).

## 2. Tipo

**Tipo D (Docker)**, dos contenedores construidos sobre imágenes oficiales con versión fija:

| Servicio | Imagen base | Qué hace |
|---|---|---|
| `ecopetrol-web` | `nginx:1.27-alpine` | Sirve el sitio estático y hace de proxy de `/api/*` hacia la API |
| `ecopetrol-api` | `node:20-alpine` | Express 4.21.2 + pg 8.13.1. Al arrancar crea el esquema y carga la semilla |
| Base de datos | PostgreSQL 16 (Dokploy *Database*) | Tablas `sedes`, `noticias`, `servicios_ti` |

```
Navegador ──HTTPS──> Traefik (Dokploy) ──> ecopetrol-web (Nginx :80)
                                             ├── /         → sitio estático (5 páginas)
                                             └── /api/*    → ecopetrol-api:3000
ecopetrol-api (Node 20) ──> PostgreSQL de Dokploy (red dokploy-network)
```

| Ruta | Contenido |
|---|---|
| `docker-compose.yml` | Producción (Dokploy). Sin puertos publicados; ambos servicios en `dokploy-network` |
| `docker-compose.dev.yml` | Solo pruebas locales: agrega `postgres:16-alpine` y publica la web en `:8080` |
| `nginx/nginx.conf` | Sitio + proxy `/api/`, `/healthz`, cabeceras de seguridad |
| `nginx/site/` | `index`, `nosotros`, `sedes`, `noticias`, `portal-ti` (.html), `styles.css`, `app.js`. Sin frameworks ni recursos externos (funciona sin internet) |
| `api/src/server.js` | Endpoints, reintentos de conexión, carga de esquema y semilla |
| `api/db/schema.sql`, `api/db/seed.sql` | Esquema y datos (idempotentes) |
| `.env.example`, `verify.sh` | Variables y comprobaciones |

### Endpoints

| Endpoint | Respuesta |
|---|---|
| `GET /api/health` | `{"status":"ok","db":"ok"}`, o **503** con `db:"error"` si la BD no responde (en ≤ 3 s) |
| `GET /api/sedes` | Lista de sedes |
| `GET /api/noticias?limit=N` | Noticias de la más reciente a la más antigua (N entre 1 y 50; por defecto 10) |
| `GET /api/servicios-ti` | Cómo conectarse a cada servicio interno, con `SERVER_IP` y `DOMINIO` ya reemplazados |

### Modelo de datos

| Tabla | Campos |
|---|---|
| `sedes` | `id`, `nombre` (único), `ciudad`, `departamento`, `tipo` (corporativa / refinería / instituto / filial), `descripcion` |
| `noticias` | `id`, `titulo` (único), `resumen`, `fecha`, `fuente_url` |
| `servicios_ti` | `id`, `nombre` (único), `protocolo`, `puerto`, `como_conectar` |

La semilla usa `ON CONFLICT DO NOTHING`, así que reiniciar o redesplegar la API no duplica filas. Los datos vienen de fuentes públicas (`research.md` §5 y §9) y cada noticia enlaza a la suya.

## 3. Puertos y protocolos

| Puerto | Dónde | Uso |
|---|---|---|
| 443/TCP | Traefik (Dokploy) | `https://www.ecopetrol-ti.duckdns.org` |
| 80/TCP | interno, `ecopetrol-web` | Traefik → Nginx. **No se publica** |
| 3000/TCP | interno, `ecopetrol-api` | Nginx → API. **No se publica** |
| 5432/TCP | interno, PostgreSQL | API → BD. **No se publica** |

## 4. Variables

| Variable | Ejemplo | Significado |
|---|---|---|
| `DATABASE_URL` | `postgresql://ecopetrol_app:<clave>@<internal-host>:5432/ecopetrol` | Conexión a PostgreSQL. **Obligatoria. No se sube al repositorio** |
| `SERVER_IP` | `172.20.10.14` | IP que muestra el Portal TI (reemplaza `{SERVER_IP}`) |
| `DOMINIO` | `ecopetrol-ti.duckdns.org` | Dominio que muestra el Portal TI (reemplaza `{DOMINIO}`) |
| `DEV_DB_PASSWORD` | `solo-pruebas-local` | Solo para `docker-compose.dev.yml` |

## 5. Datos persistentes

- Los datos viven en la base de Dokploy `ecopetrol-db`; Dokploy guarda su volumen. Los contenedores web y API **no tienen estado**: se pueden redesplegar sin perder nada.
- En pruebas locales, el volumen `ecopetrol_db_dev` guarda la BD de prueba (`docker compose ... down -v` lo borra).

## 6. Despliegue para A

1. **Base de datos.** Dokploy → proyecto `Ecopetrol-TI` → **Create Service → Database → PostgreSQL**:
   - Name `ecopetrol-db`, Database Name `ecopetrol`, Database User `ecopetrol_app`, una contraseña fuerte, imagen `postgres:16`.
   - **No** activar *External Port*.
   - Deploy. Copiar la **Internal Connection URL** de la pestaña *General*.
2. **Web.** **Create Service → Compose**, tipo **Docker Compose**:
   - Provider Git/GitHub → repositorio → branch `main` → Compose Path `./codigo/web/docker-compose.yml`.
   - **Environment**:
     ```
     DATABASE_URL=<Internal Connection URL del paso 1>
     SERVER_IP=172.20.10.14
     DOMINIO=ecopetrol-ti.duckdns.org
     ```
3. **Domains** → Add Domain: Host `www.ecopetrol-ti.duckdns.org`, Path `/`, Service Name **`ecopetrol-web`**, Container Port **80**, HTTPS **on**, Certificate Provider **None** (Traefik usa el certificado cargado; el SAN `*.ecopetrol-ti.duckdns.org` cubre `www`). Opcional: otro dominio para `ecopetrol-ti.duckdns.org` sin `www`.
4. **Deploy.** En *Logs* de `ecopetrol-api` debe salir `esquema y semilla listos: 5 sedes, 5 noticias, 6 servicios TI`.
5. **Autodeploy**: pestaña *Deployments* → copiar el webhook → GitHub → Settings → Webhooks → Add webhook (content type `application/json`, evento *push*).

Probar sin Dokploy (VM Linux con Docker):
```bash
cd codigo/web
docker network create dokploy-network          # una vez; en el servidor con Dokploy ya existe
cp .env.example .env                            # usar la DATABASE_URL de prueba que indica el archivo
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
# http://localhost:8080
```

## 7. Configuración del cliente

- Navegador en `https://www.ecopetrol-ti.duckdns.org`.
- Para no ver advertencias, importar la CA del laboratorio (`ca.crt`): Windows `certutil -addstore -f Root ca.crt` (como admin); Linux `sudo cp ca.crt /usr/local/share/ca-certificates/ecopetrol-ti.crt && sudo update-ca-certificates`; Firefox la importa aparte.
- Si el DNS de la red descarta respuestas con IP privada, usar el DNS `1.1.1.1` o el archivo `hosts` (ver `codigo/servidor/CHECKLIST.md`).

## 8. Verificación

```bash
bash codigo/web/verify.sh server                                   # en el servidor
bash codigo/web/verify.sh client                                   # en un cliente con la CA instalada
CA_CERT=~/ca.crt bash codigo/web/verify.sh client                  # si la CA no está en el sistema
```

Salida esperada en el servidor:
```
[OK]    contenedor ecopetrol-web corriendo (...)
[OK]    contenedor ecopetrol-api corriendo (...)
[OK]    nginx -t: configuración válida
[OK]    API /api/health: db ok
[OK]    Nginx -> API (/api/sedes) responde
[OK]    ecopetrol-web está en dokploy-network (Traefik lo alcanza)
[OK]    la web no publica puertos (entra solo por Traefik)
```

## 9. Problemas conocidos y solución

| Síntoma | Causa | Solución |
|---|---|---|
| `/api/*` devuelve **504** después de redesplegar o reiniciar la API (encontrado en las pruebas) | Nginx resolvía `ecopetrol-api` una sola vez al arrancar; la API volvía con otra IP | `resolver 127.0.0.11 valid=10s` y `proxy_pass` con variable: Nginx vuelve a resolver el nombre |
| `/api/health` se quedaba colgado con la BD caída (encontrado en las pruebas) | El pool de `pg` no tenía timeout de conexión | `connectionTimeoutMillis: 3000` y `query_timeout: 5000`: ahora responde 503 en 3 s |
| 502/504 en `/api` desde el principio | Nombre de servicio distinto en `proxy_pass` | Debe ser `ecopetrol-api` |
| `ENOTFOUND <host-db>` en los logs de la API | La API no está en `dokploy-network` | Declarar la red externa en el compose |
| 404 de Traefik | El dominio apunta a otro servicio o puerto | Service `ecopetrol-web`, port 80 |
| Certificado `TRAEFIK DEFAULT CERT` | Certificate Provider distinto de None, o falta el certificado | Certificate Provider **None** y certificado cargado en Settings → Certificates |
| El build falla en Dokploy y en local no | Falta `package-lock.json` en el repositorio | Subirlo (`npm ci` lo exige) |
