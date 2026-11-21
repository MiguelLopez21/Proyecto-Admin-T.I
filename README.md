# Infraestructura de TI para Ecopetrol (sede Bogotá)

Proyecto final de Administración de Infraestructura de TI, Universidad del Quindío.

Un único servidor Ubuntu, `srv-ecopetrol`, ofrece los servicios de TI de la sede Bogotá de Ecopetrol:

- un portal web con HTTPS conectado a una base de datos;
- hora centralizada;
- cuentas de usuario únicas para toda la red;
- carpetas compartidas para Linux y Windows;
- un servidor de impresión.

Los servicios que se pueden poner en contenedores se despliegan con **Dokploy** desde este repositorio. NIS y NFS se instalan en el propio servidor con scripts, porque dependen del kernel y de RPC.

## Servicios

Todos están en `172.20.10.14`, subred de la demo `172.20.10.0/28`.

| Servicio | Acceso | Puerto | Despliegue | Código |
|---|---|---|---|---|
| Web (Nginx + API Node) | `https://www.ecopetrol-ti.duckdns.org` | 443/TCP (Traefik) | Dokploy, Compose de 2 contenedores | [`codigo/web`](codigo/web) |
| Base de datos (PostgreSQL 16) | Solo red interna, sin puerto publicado | 5432 (interno) | Dokploy Database | [`codigo/web/api/db`](codigo/web/api/db) |
| NTP (chrony) | `172.20.10.14` | 123/UDP | Dokploy, Compose | [`codigo/ntp`](codigo/ntp) |
| NIS (ypserv) | Dominio NIS `ecopetrol.local` | 111, 834, 835 TCP/UDP | Host (script) | [`codigo/nis`](codigo/nis) |
| NFSv4 | `172.20.10.14:/srv/nfs/ecopetrol` y `/home/nis` | 2049/TCP | Host (script) | [`codigo/nfs`](codigo/nfs) |
| Samba | `\\172.20.10.14\administrativa` | 445/TCP | Dokploy, Compose | [`codigo/samba`](codigo/samba) |
| CUPS (impresora virtual PDF) | `http://172.20.10.14:631/printers/Ecopetrol-Bogota-PDF` | 631/TCP | Dokploy, Compose | [`codigo/cups`](codigo/cups) |
| Panel de Dokploy | `https://panel.ecopetrol-ti.duckdns.org` | 443 / 3000 TCP | Dokploy | — |

HTTPS usa una CA propia del laboratorio: cada cliente importa `ca.crt` una sola vez (ver [`documentacion.md`](documentacion.md) §3).

Usuarios comunes, con el mismo UID y GID en NIS, NFS y Samba:

| Usuario | UID | Grupo principal |
|---|---|---|
| `admin.ti` | 2001 | `ti` (3001) |
| `lab.icpet1`, `lab.icpet2` | 2011, 2012 | `icpet` (3002) |
| `fin.bogota`, `rrhh.bogota` | 2021, 2022 | `administrativa` (3003) |

Extras: cortafuegos con UFW y la cadena `DOCKER-USER` ([`codigo/servidor/ufw.sh`](codigo/servidor/ufw.sh)), y la web como Compose multicontenedor.

## Estructura del repositorio

```
├── README.md            Este archivo: resumen e instrucciones
├── analisis.md          Análisis de necesidades, justificación de servicios y tabla de requisitos
├── diagrama.mmd         Diagrama de arquitectura (Mermaid)
├── documentacion.md     Documentación técnica: instalación, verificación, capturas y problemas
├── capturas/            Evidencias, una carpeta por servicio
├── codigo/
│   ├── servidor/        Preparación de la VM, IP fija, certificado, cortafuegos y CHECKLIST.md
│   ├── web/             Nginx + API Node + esquema y datos de PostgreSQL
│   ├── ntp/             chrony en Docker
│   ├── nis/             Servidor y cliente NIS (scripts de host)
│   ├── nfs/             Servidor y cliente NFSv4 (scripts de host)
│   ├── samba/           Samba en Docker
│   └── cups/            CUPS con impresora virtual PDF en Docker
└── docs/                Documentos de apoyo
```

Cada carpeta de `codigo/` tiene su propio `README.md` con variables, puertos, despliegue, verificación y problemas conocidos. También trae un `.env.example` y un `verify.sh`.

## Cómo desplegarlo

El orden probado, con su verificación en cada paso, está en [`codigo/servidor/CHECKLIST.md`](codigo/servidor/CHECKLIST.md). En resumen:

1. **VM:** Ubuntu Server 24.04 con EFI, adaptador puente e IP fija con `netplan-60-static.yaml.example`. Después, `sudo bash codigo/servidor/preparar-servidor.sh`.
2. **Dokploy:** instalarlo con `curl -sSL https://dokploy.com/install.sh | sudo sh`, crear el proyecto `Ecopetrol-TI` y cargar el certificado generado con `codigo/servidor/generar-certificado.sh`.
3. **Servicios en Dokploy:** crear un servicio *Compose* (tipo Docker Compose) por cada uno, apuntando a este repositorio, rama `main`:

   | Servicio | Archivo compose | Variables en Environment |
   |---|---|---|
   | NTP | `./codigo/ntp/docker-compose.yml` | `ALLOW_SUBNET` |
   | Web | `./codigo/web/docker-compose.yml` | `DATABASE_URL`, `SERVER_IP`, `DOMINIO`; dominio `www.` con HTTPS |
   | Samba | `./codigo/samba/docker-compose.yml` | `SMB_USERS`, `SMB_PASSWORD`, `SMB_GROUP`, `SMB_GID` |
   | CUPS | `./codigo/cups/docker-compose.yml` | `CUPS_ADMIN_USER`, `CUPS_ADMIN_PASSWORD`, `ALLOW_SUBNET` |

   La base de datos se crea como *Database → PostgreSQL*, sin puerto externo.
4. **Servicios en el host:**
   ```bash
   cp codigo/nis/.env.example codigo/nis/.env   # poner DEMO_PASSWORD
   sudo bash codigo/nis/install.sh codigo/nis/.env
   cp codigo/nfs/.env.example codigo/nfs/.env
   sudo bash codigo/nfs/install.sh codigo/nfs/.env
   ```
   En cada cliente Linux se ejecutan `codigo/nis/client-setup.sh` y luego `codigo/nfs/client-setup.sh`.
5. **Cortafuegos (opcional, al final):**
   ```bash
   sudo IFACE=enp0s3 PUERTOS_HOST="111 834 835 2049/tcp" bash codigo/servidor/ufw.sh
   ```

Las contraseñas **no se guardan en el repositorio**. Van en las variables de entorno de Dokploy o en archivos `.env` locales, que están en `.gitignore`.

## Verificación

Cada servicio tiene su `verify.sh`, que se ejecuta en el servidor y en un cliente:

```bash
sudo bash codigo/<servicio>/verify.sh server
bash codigo/<servicio>/verify.sh client 172.20.10.14
```

| Servicio | Servidor | Cliente |
|---|---|---|
| NTP | 6/6 | Linux y Windows sincronizados |
| Web | 7/7 | 4/4 |
| NIS | 9/9 | 12/12, con login SSH real |
| NFS | 7/7 | 9/9 |
| Samba | 4/4 | 4/4 |
| CUPS | 4/4 | 2/2 |

Los resultados detallados y las capturas de cada prueba están en [`documentacion.md`](documentacion.md).
