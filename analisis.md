# Análisis de necesidades y diseño — Infraestructura de TI para Ecopetrol

> **BORRADOR v0.1 (Entregable 1).** La columna "Despliegue" sigue la propuesta recomendada en
> `docs/design/proyecto-final-ecopetrol/proposal.md` (Propuesta 3). Si el equipo elige otra, solo cambia esa columna y el diagrama.
> Valores de red fijados el 2026-11-15 (VM creada): IP `172.20.10.14`, subred `172.20.10.0/28`, dominio `ecopetrol-ti.duckdns.org`.

## 1. La empresa

**Ecopetrol S.A.** es la compañía más grande de Colombia y una empresa integrada de energía. Se fundó en 1948 y su sede corporativa está en Bogotá (Carrera 13 No. 36-24).

- Tiene más de 19.000 empleados en el grupo y en 2025 sumó 87.130 vinculaciones a través de contratistas.
- Produce más del 60 % de los hidrocarburos del país: 745.300 barriles equivalentes por día en 2025.
- Opera en varias sedes:
  - Sede corporativa en Bogotá.
  - Refinería de Barrancabermeja.
  - Refinería de Cartagena (Reficar).
  - Instituto de innovación Icpet en Piedecuesta, con 29 laboratorios y 34 plantas piloto.
  - Filiales como Cenit, Ocensa e ISA.
- Su estrategia es *"Energía que Transforma 2040"*, que incluye un programa de transformación digital y el uso de SAP.
- En julio de 2026 sufrió un ciberataque. Se robaron archivos asociados a unas 3.300 cuentas de usuario de 15 empresas del grupo y hubo un intento de ransomware que fue bloqueado.

**Alcance del proyecto.** El equipo actúa como consultor de infraestructura y diseña un **servidor de servicios para una sede**: la sede corporativa de Bogotá más un laboratorio del Icpet como piloto. El diseño se puede replicar en las demás sedes.

## 2. Necesidades y justificación de cada servicio

| # | Servicio | Necesidad de Ecopetrol | Qué resuelve |
|---|---|---|---|
| 1 | **Web institucional (Nginx) + API** | Ecopetrol cotiza en la BVC y en la NYSE (EC). Debe informar a inversionistas, contratistas y comunidades. | Portal HTTPS con información corporativa, sedes y noticias. La API lee estos datos de la base de datos. |
| 2 | **NTP** | Refinerías, oleoductos y operaciones financieras dependen de registros de eventos. Tras el ciberataque de 2026, la investigación forense necesita que todas las marcas de tiempo coincidan. | Una sola fuente de hora para toda la red, sincronizada con `pool.ntp.org`. |
| 3 | **NFS** | Los laboratorios y plantas piloto del Icpet trabajan con equipos técnicos Linux que comparten datos de ensayos. | Directorio `/srv/nfs/ecopetrol` con los proyectos técnicos y `/home/nis`, el home centralizado de los usuarios NIS, que el cliente monta en la misma ruta. |
| 4 | **NIS** | Con más de 19.000 empleados, administrar cuentas máquina por máquina no es viable. El ciberataque de 2026 comprometió cuentas de usuario. | Una base central de usuarios y grupos. Una cuenta se crea o se deshabilita en un solo lugar. |
| 5 | **CUPS** | Las sedes administrativas imprimen contratos, órdenes de trabajo y reportes de HSE. | Una cola de impresión central y compartida, con control de quién imprime. |
| 6 | **Samba** | El personal administrativo y financiero de Bogotá usa estaciones Windows/Mac. | Una carpeta compartida por área, con acceso solo para los usuarios del grupo autorizado. |
| 7 | **Base de datos (PostgreSQL vía Dokploy)** | La información corporativa de sedes, áreas y noticias debe estar estructurada y no escrita a mano en HTML. | Una base PostgreSQL gestionada por Dokploy, con backups, que consume la API web. |

Usuarios y grupos de ejemplo. Los mismos nombres de usuario se usan en todos los servicios. Las cuentas de NIS y NFS comparten UID y GID. Samba, como corre en su propio contenedor, crea sus cuentas aparte con `smbpasswd`, usando los mismos nombres:

| Grupo (GID) | Uso | Usuarios demo (UID) |
|---|---|---|
| `ti` (3001) | Administración de la infraestructura | `admin.ti` (2001) |
| `icpet` (3002) | Laboratorios (NFS) | `lab.icpet1` (2011), `lab.icpet2` (2012) |
| `administrativa` (3003) | Oficina de Bogotá (Samba) | `fin.bogota` (2021), `rrhh.bogota` (2022) |
| `lpadmin` (grupo del contenedor CUPS) | Gestión de impresoras (CUPS) | `admin.ti` |

### 2.1 Justificación detallada por servicio

#### Web, base de datos y NTP (B)
_Pendiente: justificación de B._

#### NIS y NFS (C)
_Pendiente: justificación de C._

#### Samba: compartición de archivos para Windows y macOS (D)

**Necesidad.** La sede corporativa de Ecopetrol en Bogotá concentra al personal administrativo. Ese personal necesita una carpeta común donde guardar y compartir documentos con control de acceso. Samba implementa el protocolo SMB, el que usan de forma nativa Windows y macOS, de modo que no hace falta instalar software en los clientes. (Que el personal administrativo use Windows o Mac no tiene fuente pública; es un supuesto del escenario.)

**Por qué es adecuado.**
- Acceso desde el Explorador de Windows y el Finder sin agentes adicionales.
- Autenticación por usuario y grupo: solo el grupo `administrativa` accede al recurso; no se permiten invitados.
- Seguridad actual: SMB1 desactivado y firma SMB negociada, como exige Windows 11 24H2.
- Contexto de seguridad: el incidente de julio de 2026 comprometió cuentas de usuario, lo que refuerza el control de acceso por usuario y grupo y la ausencia de acceso anónimo.

**Complementa a NFS.** NFS sirve a clientes Linux; Samba sirve a Windows/Mac. Los UID y GID coinciden con los de NIS (grupo `administrativa` 3003), así que los dueños de los archivos son coherentes entre servicios.

#### CUPS: servidor de impresión (D)

**Necesidad.** Una sede administrativa necesita imprimir de forma centralizada, con una cola única, control de quién administra y sin instalar un driver distinto en cada equipo. (La necesidad de impresión no tiene fuente pública; es un supuesto del escenario.)

**Por qué es adecuado.**
- CUPS es el estándar de impresión en Linux y habla IPP, compatible con Windows, macOS y Linux.
- Una sola cola compartida con administración restringida al grupo `lpadmin` y acceso limitado a la subred de la oficina.
- Como no hay impresora física, se usa una impresora virtual PDF que demuestra la cola completa (envío, cola, procesamiento y salida). Si se consigue una impresora real, se agrega con su URI.

Ambos servicios se entregan como contenedores Docker construidos sobre imágenes oficiales con versión fija (`alpine:3.20` y `debian:12-slim`) y se despliegan con Dokploy como Compose.

## 3. Tabla de requisitos

Servidor: VM `srv-ecopetrol` en VirtualBox 7.2 (arranque EFI), Ubuntu Server 24.04.5 LTS, 2 vCPU, 6 GB de RAM, 40 GB de disco y 2 GB de swap, red **bridged**. IP fija **`172.20.10.14/28`** en la red de la demo (hotspot, gateway `172.20.10.1`). El dominio es **`ecopetrol-ti.duckdns.org`** (DuckDNS, apunta a la IP privada).

| Servicio | Componente | Despliegue | IP / Host | Puerto | Protocolo | Tipo de servicio |
|---|---|---|---|---|---|---|
| Acceso remoto | OpenSSH | Host | 172.20.10.14 | 22 | TCP | Administración |
| Proxy inverso | Traefik (incluido en Dokploy) | Dokploy | 172.20.10.14 | 80, 443 | TCP (HTTP/HTTPS) | Enrutamiento web + TLS |
| Panel PaaS (el "Panel Admin" del diagrama de referencia) | Dokploy | Dokploy | 172.20.10.14 | 3000 (luego `panel.ecopetrol-ti.duckdns.org` por 443) | TCP | Gestión de despliegues |
| Web | Nginx (sitio, y hace de proxy de `/api`) + API Node (el "Backend API" del diagrama de referencia) | Dokploy (Compose, red `dokploy-network`) | `www.ecopetrol-ti.duckdns.org` | 443 (interno 80) | HTTPS | Aplicación web |
| Base de datos | PostgreSQL 16 | Dokploy (Database) | interno `dokploy-network` | 5432 (no se publica) | TCP | Base de datos |
| NTP | chrony (`allow 172.20.10.0/28`) | Dokploy (Compose) | 172.20.10.14 | 123 | UDP | Sincronización de tiempo |
| CUPS | cupsd + cups-pdf | Dokploy (Compose) | 172.20.10.14 | 631 | TCP (IPP/HTTP) | Impresión |
| Samba | smbd | Dokploy (Compose) | 172.20.10.14 | 445 (+139) | TCP | Archivos para Windows/Mac (SMB) |
| NFS | nfs-kernel-server (NFSv4, mismo `Domain` en `/etc/idmapd.conf` del servidor y del cliente) | Host (script) | 172.20.10.14 | 2049 | TCP | Archivos para Linux |
| NIS | ypserv, rpcbind, yppasswdd | Host (script) | 172.20.10.14, dominio NIS `ecopetrol.local` | 111, 834 (ypserv), 835 (yppasswdd) | TCP/UDP (RPC) | Autenticación centralizada |

Clientes de prueba:
- **Cliente Linux:** una VM Ubuntu en la misma red, para NFS, NIS y NTP.
- **Cliente Windows/Mac:** la máquina física, para Samba, la impresora de CUPS, la Web y la hora con `w32tm`.

## 4. Arquitectura

Ver `diagrama.mmd`. En resumen, hay dos tipos de despliegue:

- **Por Dokploy:** Traefik termina el TLS y enruta la Web por dominio. NTP, CUPS y Samba se despliegan como Compose y publican sus puertos directamente, porque no usan HTTP. PostgreSQL vive en la red interna de Dokploy.
- **En el host:** NFS y NIS se instalan con scripts versionados en `codigo/`, porque dependen del kernel (`nfsd`) y de RPC/portmapper.

## 5. Seguridad (base)

- HTTPS en todo lo web. Dokploy emite certificados de Let's Encrypt con el reto HTTP, que exige que el puerto 80 sea alcanzable desde internet. Una VM local no lo es, así que se usa un **certificado propio** firmado por una CA del laboratorio (`codigo/servidor/generar-certificado.sh`, ECDSA P-256, 397 días, SAN `ecopetrol-ti.duckdns.org`, `*.ecopetrol-ti.duckdns.org` e IP), que el enunciado permite. Al importar la CA en los clientes no hay advertencias. Lo carga Traefik/Dokploy para `www.ecopetrol-ti.duckdns.org` y `panel.ecopetrol-ti.duckdns.org`.
- Samba sin acceso de invitado (`guest ok = no`), con `valid users = @administrativa`.
- NFS exportado solo a la subred `172.20.10.0/28`, con `root_squash`.
- La consola de administración de CUPS restringida a `@lpadmin`.
- PostgreSQL sin puerto publicado.
- UFW como punto extra. Hay que tener en cuenta que Docker publica sus puertos sin pasar por UFW.
