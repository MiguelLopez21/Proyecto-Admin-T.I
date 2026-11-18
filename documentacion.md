# Documentación técnica: infraestructura de TI para Ecopetrol (sede Bogotá)

> Proyecto final de Administración de Infraestructura de TI, Universidad del Quindío.
> Esqueleto con índice y plantilla por servicio. Cada responsable completa su sección y D consolida y revisa.

## Índice

0. Introducción y entorno
1. VM y red (A)
2. Dokploy (A)
3. DNS y HTTPS (A)
4. NTP (B)
5. Base de datos (B)
6. Web (B)
7. NIS (C)
8. NFS (C)
9. Samba (D)
10. CUPS (D)
11. Integración y pruebas cruzadas (A)
12. Extras
13. Problemas generales
14. Conclusiones

## Plantilla por servicio

Cada sección de servicio (4 a 10) usa esta estructura:

```
### Objetivo
### Instalación (comandos)
### Verificación (comando y salida esperada)
### Capturas
### Problemas encontrados (mínimo 2 reales: síntoma, causa, solución)
```

Reglas: capturas enlazadas con ruta relativa `![](capturas/<servicio>/NN_nombre.png)` (GitHub distingue mayúsculas y minúsculas); sin contraseñas ni tokens visibles.

---

## 0. Introducción y entorno

_Pendiente (A y D): empresa (Ecopetrol), objetivo del proyecto, equipo, tabla de valores compartidos (IP, dominio, puertos, UID/GID), versiones de software._

## 1. VM y red (A)

### Objetivo
Un único servidor `srv-ecopetrol` que aloja todos los servicios: los web y los de red se despliegan con Dokploy y NIS/NFS en el host. Tiene IP fija y es alcanzable desde los clientes de la misma red.

### Instalación (comandos)

| Parámetro | Valor |
|---|---|
| Hipervisor | VirtualBox 7.2.6 sobre Windows 11, con AMD-V (Hyper-V desactivado en el anfitrión; ver *Problemas encontrados*) |
| SO | Ubuntu Server 24.04.5 LTS, kernel 6.8.0-149 |
| Firmware | **EFI** |
| CPU / RAM / Disco / Swap | 2 vCPU / 6 GB / 40 GB (VDI dinámico) / 2 GB |
| Gráficos | VBoxVGA |
| Red | Adaptador puente; IP fija `172.20.10.14/28`, gateway y DNS `172.20.10.1` (+ `1.1.1.1`) |
| Usuario del SO | `sysadmin` (UID 1000), sudo |

```bash
sudo bash codigo/servidor/preparar-servidor.sh   # actualización, swap 2 GB, TZ America/Bogota, NTP del host OFF
```
El NTP del host se desactiva porque el contenedor chrony (sección 4) es la única autoridad de hora; dos procesos ajustando el reloj se pelean.

IP fija con netplan (`codigo/servidor/netplan-60-static.yaml.example`), desactivando antes la red de cloud-init. El paso a paso completo está en `codigo/servidor/CHECKLIST.md`.

Snapshots (siempre con la VM apagada): `00-base-limpia` (SO preparado), `01-dokploy` (Dokploy con admin y proyecto) y `02-ntp-db` (NTP y base de datos desplegados).

### Verificación (comando y salida esperada)
```bash
free -h | grep Swap          # Swap: 2.0Gi
timedatectl                  # Time zone: America/Bogota, NTP service: inactive
ip -br a show enp0s3         # 172.20.10.14/28
```

### Capturas
![](capturas/servidor/00_instalacion-desatendida.png)
![](capturas/servidor/01_vm-config-virtualbox.png)
![](capturas/servidor/03_swap.png)
![](capturas/servidor/02_ip-fija-netplan.png)

### Problemas encontrados
| Síntoma | Causa | Solución |
|---|---|---|
| El instalador de Ubuntu 24.04 se quedaba colgado al arrancar | La VM estaba creada con firmware BIOS | Recrear la VM con **EFI** activado |
| Errores `vmwgfx` en la consola | Controlador gráfico VMSVGA | Cambiar a **VBoxVGA** |
| Al tomar un snapshot con la VM encendida, la VM se congeló y quedó *inaccessible* | VirtualBox corre sobre Hyper-V (NEM); el snapshot en caliente dejó un disco diferencial huérfano | Reparación manual del `.vbox` para volver a enlazar el disco. Regla: **snapshots solo con la VM apagada** |
| La VM arrancó sin IPv4 y no respondía por SSH | El adaptador puente estaba sobre el Wi-Fi, pero el anfitrión estaba conectado por cable | `VBoxManage controlvm srv-ecopetrol nic1 bridged "<adaptador Ethernet>"` y `sudo networkctl reconfigure enp0s3` |
| La VM tardaba ~7 min en arrancar, se congelaba 1-3 min por ratos y una vez 5 h seguidas (`soft lockup - CPU#1 stuck for 17940s!` en `journalctl -b`) | Windows tenía cargado el hipervisor de Hyper-V, así que VirtualBox no podía usar AMD-V directamente y corría en modo NEM (`VBox.log`: "NEM … Snail execution mode", "TM: Giving up catch-up"). El hipervisor lo forzaban la Integridad de memoria (VBS/HVCI), Windows Hello con inicio de sesión mejorado y la característica *Plataforma de máquina virtual* | Desactivar las cuatro cosas: `bcdedit /set hypervisorlaunchtype off`, `DeviceGuard\EnableVirtualizationBasedSecurity`=0, `Scenarios\HypervisorEnforcedCodeIntegrity\Enabled`=0, `Scenarios\WindowsHello\Enabled`=0 y `Disable-WindowsOptionalFeature VirtualMachinePlatform`; reiniciar. Comprobación: `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` = False y `VBox.log` dice "AMD-V w/ nested paging". Después: arranque y SSH en <1 min, 0 *soft lockups*. Costo: WSL2 y Docker Desktop no funcionan mientras esté así |
| Al pasar al hotspot la VM quedó sin red | El adaptador puente seguía sobre el Ethernet, que se había desconectado | `VBoxManage controlvm srv-ecopetrol nic1 bridged "<adaptador Wi-Fi>"` y `setlinkstate1 off/on` para que pidiera DHCP; luego netplan con IP fija |
| Después de fijar la IP, Swarm seguía anunciando la IP de casa (`docker node inspect self` → `192.168.1.28`) | Swarm guarda la `advertise-addr` con la que se inicializó | Respaldo de `/var/lib/docker/swarm` y `docker swarm init --force-new-cluster --advertise-addr 172.20.10.14`; los servicios y el heartbeat de 60 s se conservaron |
| SSH fallaba con `Host key verification failed` después de reconectar | El DHCP le dio otra IP a la VM (`.88` → `.28`) y esa IP no estaba en `known_hosts` | Comprobar que la huella ED25519 era la misma y agregarla con `ssh-keyscan`. La IP fija de la demo evita el problema |

## 2. Dokploy (A)

### Objetivo
PaaS autohospedado que despliega los servicios del equipo desde el repositorio de GitHub (Compose y Database), con Traefik como proxy inverso y terminación TLS.

### Instalación (comandos)
```bash
sudo ss -tulpn | grep -E ':(80|443|3000)\b'     # puertos libres
curl -sSL https://dokploy.com/install.sh | sudo sh
```
Versiones instaladas: Dokploy **v0.31.1**, Docker **28.5.0** (modo Swarm), Traefik **v3.6.25**, PostgreSQL **16** (base interna de Dokploy).

Después: crear el usuario administrador en `http://SERVER_IP:3000` y el proyecto **`Ecopetrol-TI`**.

### Verificación (comando y salida esperada)
```bash
sudo docker service ls     # dokploy 1/1, dokploy-postgres 1/1
sudo docker ps             # dokploy-traefik Up
curl -I http://localhost:3000   # 200 (o 307 a /register antes de crear el admin)
```

### Capturas
![](capturas/dokploy/01_instalacion.png)
![](capturas/dokploy/01b_instalacion-mensaje-exito.png)
![](capturas/dokploy/01c_registro-admin.png)
![](capturas/dokploy/02_contenedores-healthy.png)
![](capturas/dokploy/03_proyecto-ecopetrol.png)

### Problemas encontrados
| Síntoma | Causa | Solución |
|---|---|---|
| Dokploy no podía clonar el repositorio | El repositorio era privado | Repositorio **público** (o conectar GitHub como proveedor en Dokploy) |
| Tras el cambio de IP de la VM, Swarm reinició dos veces `dokploy` y `dokploy-postgres` | Coincidió con el cambio de red; Swarm sigue anunciando la IP con la que se inicializó (`192.168.1.88`) | Los servicios se estabilizaron solos en ~1 min. Con la IP fija se volvió a anunciar el nodo con `--advertise-addr 172.20.10.14` (§1) |
| El panel se quedaba "cargando" para siempre y luego daba *Bad Gateway*; `journalctl -u docker` mostraba `node not registered` | Cada vez que la VM se congelaba (ver §1, Hyper-V), el nodo dejaba de enviar latidos al *dispatcher* de Swarm (5 s por defecto) y Swarm reiniciaba los servicios de Dokploy | Paliativo: `docker swarm update --dispatcher-heartbeat 60s`. No bastó con congelamientos de minutos u horas; el arreglo de fondo fue quitar Hyper-V del anfitrión (§1) |

## 3. DNS y HTTPS (A)

### Objetivo
Nombres estables para la web y el panel (`www.` y `panel.ecopetrol-ti.duckdns.org`) y HTTPS sin advertencias en los clientes.

### Instalación (comandos)

**DNS.** Subdominio `ecopetrol-ti` en DuckDNS apuntando a la IP privada del servidor. DuckDNS resuelve también cualquier subdominio (`www.`, `panel.`):
```bash
curl "https://www.duckdns.org/update?domains=ecopetrol-ti&token=<TOKEN>&ip=172.20.10.14&verbose=true"
```

**Certificado.** Dokploy solo emite Let's Encrypt con el reto HTTP, que necesita el puerto 80 alcanzable desde internet; una VM en red privada no lo es. Por eso se creó una **CA propia del laboratorio** y con ella el certificado del servidor:
```bash
bash codigo/servidor/generar-certificado.sh ecopetrol-ti.duckdns.org 172.20.10.14 ~/certs
```
- CA y servidor con ECDSA P-256; el servidor vale 397 días (máximo que aceptan los navegadores).
- SAN: `ecopetrol-ti.duckdns.org`, `*.ecopetrol-ti.duckdns.org`, `IP:172.20.10.14`.
- Las claves (`*.key`) no se suben al repositorio.

**En Dokploy:**
1. Settings → Certificates → Add Certificate: `fullchain.crt` (servidor + CA) y la clave en PKCS#8. Dokploy lo guarda en `/etc/dokploy/traefik/dynamic/certificates/<id>/` (`chain.crt`, `privkey.key`, `certificate.yml`).
2. Settings → Web Server → Server Domain: `panel.ecopetrol-ti.duckdns.org`, HTTPS on, Certificate Provider **None**. Traefik elige el certificado por SNI.

**En los clientes:** importar `ca.crt` como raíz de confianza (Windows: `certutil -addstore -f Root ca.crt`).

### Verificación (comando y salida esperada)
```bash
nslookup www.ecopetrol-ti.duckdns.org                                        # 172.20.10.14
curl -sSI --cacert ~/certs/ca.crt https://panel.ecopetrol-ti.duckdns.org     # HTTP/2 200, sin -k
echo | openssl s_client -connect panel.ecopetrol-ti.duckdns.org:443 \
  -servername panel.ecopetrol-ti.duckdns.org -CAfile ~/certs/ca.crt 2>/dev/null | grep 'Verify return code'   # 0 (ok)
```

### Capturas
![](capturas/servidor/10_dns-nslookup.png)
![](capturas/servidor/11_certificado-generado.png)
![](capturas/dokploy/04_certificado-cargado.png)
![](capturas/dokploy/05_dominio-https.png)
![](capturas/dokploy/06_panel-https.png)
![](capturas/servidor/12_curl-https-sin-k.png)

### Problemas encontrados
| Síntoma | Causa | Solución |
|---|---|---|
| No se puede usar Let's Encrypt desde Dokploy | El reto HTTP necesita que el puerto 80 sea accesible desde internet; la VM está en red privada | CA propia + certificado con SAN de dominio, comodín e IP, cargado en Dokploy con proveedor **None** |
| No se pudo agregar la línea de prueba al archivo `hosts` de Windows (`Access denied`, luego `Stream was not readable`) | El archivo tiene atributo de solo lectura y estaba bloqueado por otro proceso | Para probar en casa se apuntó DuckDNS temporalmente a la IP de casa; con la IP fija se volvió a `172.20.10.14` (2026-11-18) y se validó otra vez el HTTPS sin `-k` |
| (Riesgo previsto) `nslookup` falla en algunas redes | Protección contra *DNS rebinding* del router: descarta respuestas con IP privada | El router de casa no la tiene. Si pasa en la demo: DNS `1.1.1.1` en el cliente o archivo `hosts` |

## 4. NTP (B)

### Objetivo
Una sola fuente de hora para toda la red de la oficina. El servidor se sincroniza con `pool.ntp.org` y `south-america.pool.ntp.org` y sirve esa hora por 123/UDP solo a la subred de la demo (`172.20.10.0/28`). Así coinciden los registros de todos los servicios (clave para la investigación forense tras el ciberataque de 2026), y NIS, Samba y los certificados HTTPS no fallan por diferencias de reloj. Código y detalle en `codigo/ntp/README.md`.

### Instalación (comandos)
Contenedor propio sobre `alpine:3.20` con **chrony 4.5**, desplegado en Dokploy como **Compose tipo Docker Compose** (no *Stack*: Swarm ignora `cap_add`).

```bash
# En el servidor, antes de desplegar
sudo timedatectl set-ntp false      # el NTP del host se apaga: chrony del contenedor es la única autoridad
sudo ss -ulpn | grep ':123 '        # el puerto debe estar libre
```

En Dokploy: proyecto `Ecopetrol-TI` → Create Service → Compose `ntp`, branch `main`, Compose Path `./codigo/ntp/docker-compose.yml`, y en *Environment*:
```
ALLOW_SUBNET=172.20.10.0/28
AJUSTAR_RELOJ=true
TZ=America/Bogota
```

Decisiones de configuración:
- `cap_add: SYS_TIME`: el contenedor comparte el kernel con el host, así que chrony corrige el reloj **de todo el servidor**.
- `makestep 1.0 3`: si al arrancar el desfase es mayor que 1 s, lo corrige de un salto; después, de forma gradual.
- `local stratum 10`: si la demo se queda sin internet, el servidor sigue sirviendo su reloj y los clientes quedan sincronizados entre sí.
- `ALLOW_SUBNET` admite varias subredes separadas por coma; el *entrypoint* genera una línea `allow` por cada una. Durante las pruebas en casa se agregó `192.168.1.0/24`.

Clientes (detalle en el README del servicio):
```bash
# Linux con chrony
echo 'server 172.20.10.14 iburst prefer' | sudo tee /etc/chrony/sources.d/ecopetrol.sources
sudo systemctl restart chrony && chronyc sources        # la línea de 172.20.10.14 empieza con ^*
```
```powershell
# Windows (PowerShell como administrador)
w32tm /config /manualpeerlist:172.20.10.14 /syncfromflags:manual /reliable:no /update
w32tm /resync; w32tm /query /source                     # 172.20.10.14
```

### Verificación (comando y salida esperada)
```bash
bash codigo/ntp/verify.sh server        # 6/6 [OK]: contenedor, Leap status Normal, fuente ^*, allow, 123/udp, NTP del host inactivo
docker exec <ntp> chronyc tracking      # Stratum 3, Leap status Normal, "System time" en milisegundos
docker exec <ntp> chronyc clients       # lista los equipos que consultaron la hora
```
Resultado en el servidor (2026-11-18): estrato 3, `Leap status: Normal`, desfase de **1,6 ms**, 5 fuentes válidas. Desde Windows, `w32tm /stripchart /computer:172.20.10.14` responde.

### Capturas
![](capturas/ntp/01_build-local.png)
![](capturas/ntp/02_chronyc-sources-servidor.png)
![](capturas/ntp/05_dokploy-verify-server.png)

_Pendiente: `ntp/03_cliente-linux` (`chronyc sources` con `^*` en el cliente Linux) y `ntp/04_windows-w32tm-source`._

### Problemas encontrados
| Síntoma | Causa | Solución |
|---|---|---|
| En los logs de chrony: `System clock was stepped by 60954.902717 seconds` (casi 17 h) | La VM se había congelado y VirtualBox la dejó en estado *guardado* al apagar Windows; al reanudarla, su reloj seguía en la hora en que se detuvo | `makestep 1.0 3` corrigió el reloj de un salto al arrancar chrony. Sin un servidor NTP en la red, todos los registros de esas horas habrían quedado con la fecha equivocada |
| En cada arranque de la VM, chrony corregía unos 6 s (`stepped by 5.937311 seconds`, `6.492441 seconds`) | La VM toma la hora inicial del reloj de Windows, que estaba unos 4-6 s desfasado (`w32tm /stripchart` contra el servidor mostraba `+04.15s`) | Lo corrige `makestep`. Configurar Windows como cliente del servidor (`w32tm`, arriba) también arregla el reloj del anfitrión |
| El contenedor de prueba y el de Dokploy no pueden estar a la vez | Los dos publican 123/UDP: el segundo falla con `address already in use` | Apagar el de prueba (`docker compose down` en `~/pruebas/ntp`) antes de desplegar en Dokploy |
| (Previsto en el diseño) `adjtimex(0x8001) failed: Operation not permitted` | Falta `SYS_TIME`, o la app se crea como *Stack*, que ignora `cap_add` | `cap_add: SYS_TIME` y app tipo **Docker Compose** |

## 5. Base de datos (B)

### Objetivo
Guardar la información del portal (sedes, noticias y la guía de servicios TI) en una base **PostgreSQL 16** administrada por Dokploy, para que la web no tenga datos escritos a mano en HTML. La base solo es accesible desde la red interna de Docker: no se publica ningún puerto.

### Instalación (comandos)
En Dokploy: proyecto `Ecopetrol-TI` → Create Service → **Database → PostgreSQL**:

| Campo | Valor |
|---|---|
| Name | `ecopetrol-db` (servicio `ecopetrolti-ecopetroldb-5fzqvb`) |
| Database Name / User | `ecopetrol` / `ecopetrol_app` |
| Contraseña | generada, fuerte; solo en Dokploy |
| Imagen | `postgres:16` (16.16) |
| External Port | **desactivado** |

Deploy, y copiar la **Internal Connection URL** (`postgresql://ecopetrol_app:<clave>@ecopetrolti-ecopetroldb-5fzqvb:5432/ecopetrol`) a la variable `DATABASE_URL` de la web (§6).

El esquema y los datos no se cargan a mano: la API ejecuta `codigo/web/api/db/schema.sql` y `seed.sql` al arrancar. Son idempotentes (`CREATE TABLE IF NOT EXISTS`, `ON CONFLICT DO NOTHING`), así que redesplegar no duplica filas.

| Tabla | Campos |
|---|---|
| `sedes` | `id`, `nombre` (único), `ciudad`, `departamento`, `tipo`, `descripcion` |
| `noticias` | `id`, `titulo` (único), `resumen`, `fecha`, `fuente_url` |
| `servicios_ti` | `id`, `nombre` (único), `protocolo`, `puerto`, `como_conectar` |

Los datos viven en el volumen `ecopetrolti-ecopetroldb-5fzqvb-data`; los contenedores de la web no tienen estado. Dokploy permite programar backups de la base (pestaña *Backups*).

### Verificación (comando y salida esperada)
```bash
c=$(sudo docker ps -qf name=ecopetrolti-ecopetroldb)
sudo docker exec $c psql -U ecopetrol_app -d ecopetrol -c '\dt'      # noticias, sedes, servicios_ti
sudo docker exec $c psql -U ecopetrol_app -d ecopetrol \
  -c 'select (select count(*) from sedes) sedes, (select count(*) from noticias) noticias, (select count(*) from servicios_ti) servicios_ti;'
# sedes 5 | noticias 5 | servicios_ti 6
sudo docker service inspect ecopetrolti-ecopetroldb-5fzqvb --format '{{json .Endpoint.Ports}}'   # null: sin puertos publicados
curl -s https://www.ecopetrol-ti.duckdns.org/api/health                                          # {"status":"ok","db":"ok"}
```

### Capturas
![](capturas/web/05_bd-dokploy.png)
![](capturas/web/02_pagina-sedes-desde-bd.png)

### Problemas encontrados
| Síntoma | Causa | Solución |
|---|---|---|
| `docker service ps` muestra dos tareas de la base en `Failed` con `No such container: ecopetrolti-ecopetroldb-5fzqvb.1...` | La base corre como servicio de Swarm; cuando la VM se congelaba (Hyper-V, §1), Swarm perdía el contenedor y creaba una tarea nueva | Swarm la recreó sola y **no se perdieron datos**, porque están en el volumen `...-data`, no en el contenedor. El arreglo de fondo fue quitar Hyper-V del anfitrión (§1) |
| Con la base caída, `/api/health` se quedaba colgado en lugar de avisar (encontrado en las pruebas) | El *pool* de `pg` de la API no tenía tiempo límite de conexión | `connectionTimeoutMillis: 3000` y `query_timeout: 5000`: ahora responde **503** con `"db":"error"` en 3 s |
| El host de la base no es `ecopetrol-db` sino `ecopetrolti-ecopetroldb-5fzqvb` | Dokploy agrega el proyecto y un sufijo aleatorio al nombre del servicio | Usar siempre la **Internal Connection URL** que muestra Dokploy, no armarla a mano |

## 6. Web (B)

### Objetivo
Portal HTTPS de la sede Bogotá en `https://www.ecopetrol-ti.duckdns.org`: información corporativa, sedes y noticias leídas de la base de datos (§5), y un "Portal TI" con la forma de conectarse a cada servicio de la red. Código y detalle en `codigo/web/README.md`.

### Instalación (comandos)
Dos contenedores en un Compose de Dokploy, sin puertos publicados (todo entra por Traefik):

```
Navegador ──HTTPS──> Traefik (Dokploy) ──> ecopetrol-web (Nginx 1.27 :80)
                                             ├── /       → sitio estático (5 páginas)
                                             └── /api/*  → ecopetrol-api (Node 20 :3000) ──> PostgreSQL (§5)
```

En Dokploy: Create Service → **Compose** `web`, tipo Docker Compose, branch `main`, Compose Path `./codigo/web/docker-compose.yml`.
- *Environment*: `DATABASE_URL=<Internal Connection URL de §5>`, `SERVER_IP=172.20.10.14`, `DOMINIO=ecopetrol-ti.duckdns.org`.
- *Domains*: host `www.ecopetrol-ti.duckdns.org`, path `/`, service **`ecopetrol-web`**, puerto **80**, HTTPS activado, Certificate Provider **None** (Traefik usa el certificado de la CA propia, §3).
- Deploy. En los logs de la API: `[db] esquema y semilla listos: 5 sedes, 5 noticias, 6 servicios TI`.

**Autodeploy.** Como el servidor tiene IP privada, GitHub no puede llamar al webhook de Dokploy. El servidor revisa GitHub cada minuto (`git ls-remote`) con un timer de systemd y, si `main` cambió, llama él mismo al webhook con el formato de GitHub (`codigo/web/autodeploy/`, instalación en el README de la web §6):
```bash
sudo systemctl enable --now autodeploy-sondeo.timer
journalctl -u autodeploy-sondeo        # Cambio en main: 406053e -> 3ee778b / Dokploy: Compose deployed successfully
```
La URL del webhook es un secreto: queda en `/etc/ecopetrol/autodeploy.env` (solo root), no en el repositorio.

### Verificación (comando y salida esperada)
```bash
bash codigo/web/verify.sh server                          # 7/7 [OK]: contenedores, nginx -t, health, Nginx→API, red dokploy-network, sin puertos publicados
CA_CERT=~/certs/ca.crt bash codigo/web/verify.sh client   # 4/4 [OK]: HTTPS 200 sin -k, db ok, 5 sedes, cabeceras de seguridad
curl -s https://www.ecopetrol-ti.duckdns.org/api/health   # {"status":"ok","db":"ok"}
```
Prueba de autodeploy (2026-11-18): el push del commit `3ee778b` se desplegó solo en menos de 1 minuto (despliegue de 4 s en Dokploy).

### Capturas
![](capturas/web/01_sitio-https-candado.png)
![](capturas/web/02_pagina-sedes-desde-bd.png)
![](capturas/web/03_api-health.png)
![](capturas/web/04_dokploy-dominio.png)
![](capturas/web/06_autodeploy.png)
![](capturas/web/06b_autodeploy-sondeo.png)

### Problemas encontrados
| Síntoma | Causa | Solución |
|---|---|---|
| `/api/*` devolvía **504** después de redesplegar o reiniciar la API (encontrado en las pruebas) | Nginx resolvía el nombre `ecopetrol-api` una sola vez al arrancar, y la API volvía con otra IP | `resolver 127.0.0.11 valid=10s` y `proxy_pass` con variable, para que Nginx vuelva a resolver el nombre |
| El autodeploy con el webhook de GitHub no se puede usar | GitHub tendría que conectarse a `172.20.10.14`, una IP privada detrás del hotspot | Sondeo desde el servidor (`autodeploy-sondeo.timer`): solo hace conexiones de salida y no hay que abrir nada a internet |
| El webhook de Dokploy respondía `301 {"message":"Branch Not Match"}` | Dokploy lee la rama del campo `ref` del cuerpo y la cabecera `X-GitHub-Event`; una llamada simple no los trae | El script envía `X-GitHub-Event: push` y un cuerpo con el formato de GitHub (`ref`, `after`, mensaje y archivos del commit) |
| `verify.sh client` fallaba en el servidor con `curl failed to verify the legitimacy of the server` | La VM no tenía la CA del laboratorio en su almacén de certificados | `CA_CERT=~/certs/ca.crt`, o instalar la CA en el sistema (`update-ca-certificates`) |

## 7. NIS (C)

### Objetivo
_Pendiente (C)._
### Instalación (comandos)
### Verificación (comando y salida esperada)
### Capturas
### Problemas encontrados

## 8. NFS (C)

### Objetivo
_Pendiente (C)._
### Instalación (comandos)
### Verificación (comando y salida esperada)
### Capturas
### Problemas encontrados

## 9. Samba (D)

### Objetivo
Compartir la carpeta `administrativa` con clientes Windows, macOS y Linux, con autenticación por usuario, sin invitados y sin SMB1. Corre en un contenedor Alpine 3.20 (`codigo/samba/`), desplegado con Dokploy.

### Instalación (comandos)
```bash
cd codigo/samba
cp .env.example .env            # editar SMB_PASSWORD
docker compose up -d --build
docker compose logs -f samba
```
En Dokploy: servicio Compose, *Compose Path* `./codigo/samba/docker-compose.yml`, variables en la pestaña *Environment*.

### Verificación (comando y salida esperada)
```bash
bash codigo/samba/verify.sh server            # [OK] en las 4 comprobaciones, exit 0
bash codigo/samba/verify.sh client SERVER_IP   # con SMB_PASSWORD exportada
```
- `docker exec <samba> pdbedit -L` lista `fin.bogota`, `rrhh.bogota` y `admin.ti`.
- `smbclient //SERVER_IP/administrativa -U lab.icpet1 -c ls` → `NT_STATUS_LOGON_FAILURE` o `ACCESS_DENIED`.
- Windows: `net use Z: \\SERVER_IP\administrativa /user:ECOPETROL\fin.bogota *` y crear un archivo.

### Capturas
_Pendiente: `samba/01_build-local`, `02_testparm`, `03_pdbedit-usuarios`, `04_windows-explorador`, `05_net-use-Z`, `06_escribir-archivo`, `07_usuario-no-autorizado-denegado`, `08_mac-o-linux-smbclient`._

### Problemas encontrados
_Pendiente: completar con los problemas reales de las pruebas (mínimo 2). Candidatos a revisar: `bind failed on port 445`, error 1219 de Windows por credencial en caché, permisos al escribir._

## 10. CUPS (D)

### Objetivo
Publicar una impresora virtual PDF (`Ecopetrol-Bogota-PDF`) compartida por IPP, administrable solo por `lpadmin`, accesible desde la subred de la oficina. Corre en un contenedor Debian 12 (`codigo/cups/`), desplegado con Dokploy.

### Instalación (comandos)
```bash
cd codigo/cups
cp .env.example .env            # editar CUPS_ADMIN_PASSWORD y ALLOW_SUBNET
docker compose up -d --build
docker compose logs -f cups
```
En Dokploy: servicio Compose, *Compose Path* `./codigo/cups/docker-compose.yml`.

### Verificación (comando y salida esperada)
```bash
bash codigo/cups/verify.sh server             # scheduler is running, cola idle/enabled, :631 abierto
bash codigo/cups/verify.sh client SERVER_IP   # request id is Ecopetrol-Bogota-PDF-N
docker exec <cups> ls -l /var/spool/cups-pdf/ANONYMOUS   # aparece el PDF nuevo
```
- Administración web: `https://SERVER_IP:631/admin` con `admin.ti` (certificado autofirmado, se acepta la advertencia).
- Windows: agregar la impresora por `http://SERVER_IP:631/printers/Ecopetrol-Bogota-PDF` con *Microsoft PS Class Driver* e imprimir una página de prueba.

### Capturas
_Pendiente: `cups/01_web-admin`, `02_cola-compartida`, `03_windows-agregar-impresora`, `04_pagina-prueba`, `05_lpstat-cola`, `06_pdf-generado`._

### Problemas encontrados
_Pendiente: completar con los problemas reales de las pruebas (mínimo 2). Candidatos a revisar: `400 Bad Request` sin `ServerAlias *`, `403` por usar `@LOCAL`, cola en *stopped*, driver en Windows._

## 11. Integración y pruebas cruzadas (A)

Orden de despliegue y comandos en `codigo/servidor/CHECKLIST.md` §7. Estado al 2026-11-18 (servidor en `172.20.10.14`):

| Servicio | Despliegue | `verify.sh server` | Prueba de cliente | Captura |
|---|---|---|---|---|
| NTP | Dokploy (Compose) | 6/6 OK | Windows `w32tm /stripchart` responde; Linux `^*` _pendiente_ | `ntp/05_dokploy-verify-server.png` |
| Base de datos | Dokploy (Database) | — | _pendiente (desde la web)_ | `web/05_bd-dokploy.png` |
| Web | _pendiente_ | | | |
| NIS | _pendiente (C)_ | | | |
| NFS | _pendiente (C)_ | | | |
| Samba | _pendiente (D)_ | | | |
| CUPS | _pendiente (D)_ | | | |

## 12. Extras

- **Cortafuegos (A):** `codigo/servidor/ufw.sh`. UFW por sí solo no protege los puertos de los contenedores, porque Docker los publica en la cadena `FORWARD` antes de que UFW los vea. El script pone UFW con política *deny* para el anfitrión (SSH y los puertos de NIS/NFS) y filtra la cadena `DOCKER-USER` para que a los contenedores solo lleguen las subredes permitidas. Probado: desde una subred no permitida el panel (3000) y el HTTPS (443) dan *timeout* y el kernel registra `[DOCKER-USER BLOQUEADO]`; SSH y la salida a internet de los contenedores siguen funcionando, y las reglas sobreviven a un reinicio. Se activa al final, con todos los servicios desplegados (`CHECKLIST.md` §7b).
- _Pendiente: backup automático, monitoreo, Docker Compose multi-contenedor._

## 13. Problemas generales

- **Red de la demo:** se eligió el hotspot de un celular (subred `172.20.10.0/28`) para tener la misma red en casa y en la universidad, porque muchas redes Wi-Fi universitarias aíslan clientes o rechazan una segunda MAC en el adaptador puente. Ojo: es una **/28**, no una /24, y eso afecta `allow` de chrony, `exports` de NFS y los `Allow` de Samba/CUPS.
- **VirtualBox y Hyper-V no conviven bien:** en Windows 11 el hipervisor puede quedar activo aunque Hyper-V "no esté instalado" (Windows Home), por la Integridad de memoria, Windows Hello mejorado o WSL2. VirtualBox arranca igual, pero en modo NEM, lento e inestable. Hay que revisarlo antes de montar cualquier servidor en VirtualBox (detalle en §1).
- **Certificado propio:** cada cliente tiene que importar `ca.crt` una vez; Firefox usa su propio almacén.
- _Pendiente (C y D): UID/GID entre servicios._

## 14. Conclusiones

_Pendiente: resultados, lecciones aprendidas, análisis costo-beneficio._
