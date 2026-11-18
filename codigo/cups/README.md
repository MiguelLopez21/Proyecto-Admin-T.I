# CUPS: servidor de impresión de la oficina Bogotá (Ecopetrol)

Servidor CUPS en un contenedor Debian 12 con una **impresora virtual PDF** (`cups-pdf`) compartida como `Ecopetrol-Bogota-PDF`. Cada trabajo de impresión genera un PDF en un volumen, lo que demuestra la cola completa: envío → cola → procesamiento → salida. Si el equipo consigue una impresora real, se agrega además con su URI (`ipp://…` o `socket://…:9100`).

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `Dockerfile` | Imagen `debian:12-slim` con `cups`, `cups-client`, `cups-bsd`, `printer-driver-cups-pdf` y `tini` |
| `config/cupsd.conf` | Configuración de CUPS (acceso por subred, `ServerAlias *`) |
| `config/cups-pdf.conf` | Carpetas de salida de los PDF |
| `entrypoint.sh` | Genera la configuración, crea el admin, arranca `cupsd` y crea la cola |
| `docker-compose.yml` | Servicio `cups`, puerto 631, volúmenes `cups_config` y `cups_pdf` |
| `.env.example` | Variables de ejemplo (copiar a `.env`) |
| `verify.sh` | Comprobaciones `server` y `client` |

## Variables de entorno

| Variable | Ejemplo | Descripción |
|---|---|---|
| `CUPS_ADMIN_USER` | `admin.ti` | Usuario administrador (grupo `lpadmin`) |
| `CUPS_ADMIN_PASSWORD` | `cambiar` | Clave del administrador. **Cambiarla; no se sube al repositorio** |
| `ALLOW_SUBNET` | `192.168.1.0/24` | Subred de los clientes autorizados (la de la VM en bridged) |

## Decisiones importantes

- **Acceso por subred explícita, no `@LOCAL`.** Dentro del contenedor `@LOCAL` es la red de Docker (172.x) y los clientes (192.168.x) recibirían `403`. El entrypoint reemplaza `${ALLOW_SUBNET}` en `cupsd.conf` en cada arranque.
- **`ServerAlias *`.** Sin él, CUPS responde `400 Bad Request` cuando llegan con la IP u otro nombre.
- **No usar `cupsctl --remote-any` ni `--share-printers`.** Reescriben `cupsd.conf` y borran la restricción por subred. La cola se comparte con `printer-is-shared=true`.
- **Administración solo para `lpadmin`** y desde la subred permitida.
- `SystemGroup lpadmin root` y los logs a stderr se escriben en `cups-files.conf`, que es donde CUPS 2.x los lee.

## Requisitos del servidor

- VM Linux con Docker y el puerto 631 libre (si el host tiene `cups` instalado, desactivarlo: `sudo systemctl disable --now cups cups-browsed`).

## Probar en local

```bash
cd codigo/cups
cp .env.example .env          # editar CUPS_ADMIN_PASSWORD y ALLOW_SUBNET
docker compose up -d --build
docker compose logs -f cups
bash verify.sh server
```

## Desplegar en Dokploy

1. Servicio tipo **Compose**, *Compose Path* `./codigo/cups/docker-compose.yml`.
2. Pestaña *Environment*: `CUPS_ADMIN_USER`, `CUPS_ADMIN_PASSWORD`, `ALLOW_SUBNET`.
3. Deploy y revisar *Logs*.

## Conectar desde los clientes

Reemplazar `SERVER_IP` por la IP del servidor.

- **Linux, sin crear cola local:**
  `lp -h SERVER_IP:631 -d Ecopetrol-Bogota-PDF /etc/hostname` y luego `lpstat -h SERVER_IP:631 -o`.
- **Linux, con cola local:**
  `sudo lpadmin -p ecopetrol -E -v ipp://SERVER_IP:631/printers/Ecopetrol-Bogota-PDF -m everywhere`. Si `everywhere` falla, usar `-m raw`.
- **Windows:** Configuración → Impresoras y escáneres → Agregar → *La impresora que deseo no está en la lista* → *Seleccionar una impresora compartida por nombre* → `http://SERVER_IP:631/printers/Ecopetrol-Bogota-PDF`.
  Driver: **Microsoft PS Class Driver** (o *Generic → MS Publisher Color Printer*), porque cups-pdf recibe PostScript. Imprimir una página de prueba.
- **Administración web:** `https://SERVER_IP:631/admin` con el usuario `admin.ti`. El navegador avisa por el certificado autofirmado de CUPS; se acepta.

## Verificación

```bash
# En el servidor
bash verify.sh server

# Desde un cliente Linux con cups-client
bash verify.sh client SERVER_IP

# De vuelta en el servidor: el PDF generado
docker exec <contenedor-cups> ls -l /var/spool/cups-pdf/ANONYMOUS
```

Resultado esperado: `scheduler is running`, la cola en `idle`/`enabled`, `request id is Ecopetrol-Bogota-PDF-N` y un PDF nuevo.

## Problemas típicos

| Síntoma | Causa | Solución |
|---|---|---|
| `400 Bad Request` | Falta `ServerAlias *` | Agregarlo |
| `403 Forbidden` desde la red | Se usó `Allow @LOCAL` o `ALLOW_SUBNET` no coincide con la red de los clientes | `Allow from SUBRED` correcta |
| La cola se queda *stopped* | PPD o backend cups-pdf mal | `lpinfo -v` debe listar `cups-pdf:/`; revisar el PPD con `lpinfo -m \| grep -i pdf` |
| No aparece el PDF | Ruta `Out` o permisos del spool | Revisar `cups-pdf.conf` y el volumen `cups_pdf` |
| Windows no instala la impresora | Driver | Usar *Microsoft PS Class Driver* |
