# NIS: autenticación centralizada de usuarios (ypserv)

## 1. Servicio y responsable

Servidor **NIS maestro** en `srv-ecopetrol` para el dominio `ecopetrol.local`. Las cuentas de los empleados (TI, laboratorios del Icpet y oficina administrativa) se crean una sola vez en el servidor y cualquier equipo Linux de la red las usa para iniciar sesión, con los mismos UID y GID que NFS y Samba. Ver la justificación en [`analisis.md`](../../analisis.md).

Responsable: C (NIS + NFS).

## 2. Tipo

**Tipo H (host).** Corre directamente en Ubuntu 24.04, no en Docker, porque depende de `rpcbind` y RPC. Paquetes de Ubuntu 24.04: `nis` (ypserv, yppasswdd, ypbind) y `rpcbind`.

| Archivo | Para qué sirve |
|---|---|
| `install.sh` | Servidor NIS maestro: dominio, usuarios y grupos desde los CSV, puertos fijos, securenets, mapas |
| `client-setup.sh` | Cliente Ubuntu 24.04: `yp.conf`, `nsswitch.conf`, drop-in de `systemd-logind`, `ypbind` |
| `config/grupos.csv` | `grupo,gid` |
| `config/usuarios.csv` | `usuario,uid,grupo,grupos_extra,nombre` (los grupos extra van separados por `;`) |
| `.env.example` | Variables de ejemplo |
| `verify.sh` | Comprobaciones `server` y `client` |

## 3. Puertos y protocolos

| Puerto | Protocolo | Uso |
|---|---|---|
| 111 | TCP/UDP | `rpcbind` (portmapper) |
| 834 | TCP/UDP | `ypserv` (fijo con `YPSERVARGS="-p 834"`) |
| 835 | TCP/UDP | `yppasswdd` (fijo con `YPPASSWDDARGS="--port 835"`) |

Los puertos son fijos para poder abrirlos en el cortafuegos (`codigo/servidor/ufw.sh`, variable `PUERTOS_HOST`).

## 4. Variables

| Variable | Ejemplo | Significado |
|---|---|---|
| `NIS_DOMAIN` | `ecopetrol.local` | Dominio NIS (no es un dominio DNS) |
| `SERVER_IP` | `172.20.10.14` | IP del servidor NIS (la usa el cliente en `/etc/yp.conf`) |
| `SUBRED_NET` | `172.20.10.0` | Red que puede consultar NIS (`/etc/ypserv.securenets`) |
| `SUBRED_MASK` | `255.255.255.240` | Máscara de esa red. La demo usa una **/28**, no una /24 |
| `DEMO_PASSWORD` | `cambiar` | Contraseña inicial de los 5 usuarios. Solo se fija al crearlos. **No se sube al repo** |

## 5. Datos persistentes

| Ruta | Contenido |
|---|---|
| `/etc/passwd`, `/etc/shadow`, `/etc/group` | Las cuentas reales (fuente de los mapas) |
| `/var/yp/ecopetrol.local/` | Mapas NIS generados (`passwd.byname`, `group.byname`, …) |
| `/home/nis/<usuario>` | Homes de los usuarios NIS (`700`, del usuario). Se exportan por NFS |
| `/etc/default/nis.orig` | Copia del archivo original antes de modificarlo |

### Usuarios y grupos

| Usuario | UID | Grupo principal | Grupos extra |
|---|---|---|---|
| `admin.ti` | 2001 | `ti` (3001) | `icpet`, `administrativa` |
| `lab.icpet1` | 2011 | `icpet` (3002) | — |
| `lab.icpet2` | 2012 | `icpet` (3002) | — |
| `fin.bogota` | 2021 | `administrativa` (3003) | — |
| `rrhh.bogota` | 2022 | `administrativa` (3003) | — |

### Decisiones de configuración

- **`MINUID=2000` y `MINGID=2000`** en `/var/yp/Makefile`: solo se exportan las cuentas del proyecto. Con 1000 se publicaría `sysadmin` (UID 1000, administrador del servidor) con su hash de contraseña, y chocaría con el usuario local UID 1000 de cada cliente.
- **securenets** solo con `127.0.0.0/8` y la subred de la demo; se elimina la línea `0.0.0.0 0.0.0.0`, que abre NIS a cualquiera.
- **`NISCLIENT=false`** en el servidor: no se consulta a sí mismo; sus usuarios ya están en `/etc/passwd`.
- **Limitación conocida de NIS**: los hashes de contraseña viajan en los mapas (`MERGE_PASSWD=true`) y sin cifrar. Es aceptable en una LAN cerrada de laboratorio; en producción se usaría LDAP + Kerberos (ver `documentacion.md`).

## 6. Despliegue para A

En `srv-ecopetrol`, desde la raíz del repositorio clonado:

1. `cp codigo/nis/.env.example codigo/nis/.env` y poner la contraseña de demo acordada en `DEMO_PASSWORD`.
2. `sudo bash codigo/nis/install.sh codigo/nis/.env`
3. Al terminar imprime `rpcinfo` (ypserv en 834, yppasswdd en 835) y `ypcat passwd` con los 5 usuarios.
4. `bash codigo/nis/verify.sh server` → todo `[OK]`.
5. Abrir los puertos al activar el cortafuegos: `sudo PUERTOS_HOST="111 834 835 2049/tcp" bash codigo/servidor/ufw.sh`.

**Regla:** cada vez que se cree o cambie un usuario en el servidor, ejecutar `sudo make -C /var/yp`. Si no, los clientes no ven el cambio.

El script es idempotente: se puede volver a ejecutar sin duplicar nada. Si un usuario o grupo ya existe con otro UID/GID, se detiene con un mensaje en vez de dejar IDs inconsistentes.

## 7. Configuración del cliente (Linux, `cli-icpet`)

1. Copiar `codigo/nis/` al cliente, crear su `.env` (basta con `NIS_DOMAIN` y `SERVER_IP`; agrega `DEMO_PASSWORD` si quieres que `verify.sh client` pruebe el login, e instala `sshpass`).
2. `sudo bash client-setup.sh .env`
3. Después configurar NFS (`codigo/nfs/client-setup.sh`), que monta los homes `/home/nis`.

## 8. Verificación

```bash
# Servidor
bash verify.sh server
#   servicios rpcbind/ypserv/yppasswdd activos, puertos 834/835, securenets cerrado,
#   5 usuarios en el mapa, ninguna cuenta con UID < 2000

# Cliente
DEMO_PASSWORD='<la de demo>' bash verify.sh client 172.20.10.14
#   ypwhich → 172.20.10.14, nsswitch con nis, drop-in de logind,
#   getent passwd lab.icpet1 → UID 2011, id fin.bogota → administrativa(3003)
#   y, si está instalado sshpass, login SSH real y contraseña incorrecta rechazada
```

Prueba manual de la rúbrica (autenticación real): en el cliente, `ssh lab.icpet1@localhost` pide la contraseña NIS; tras entrar, `pwd` devuelve `/home/nis/lab.icpet1`. Con una contraseña incorrecta, `Permission denied`.

Capturas mínimas: `capturas/nis/01_install-servidor`, `02_rpcinfo-puertos-fijos`, `03_ypcat-passwd`, `04_cliente-ypwhich`, `05_login-ssh-lab.icpet1`, `06_contrasena-incorrecta-rechazada`.

## 9. Problemas conocidos y solución

| Síntoma | Causa | Solución |
|---|---|---|
| `ypwhich: Can't communicate with ypbind` | `ypbind` caído o falta `/etc/defaultdomain` | Revisar el dominio y `systemctl status ypbind` |
| `getent` funciona pero el login se cuelga | `systemd-logind` trae `IPAddressDeny=any` y bloquea las consultas NIS | Drop-in `IPAddressAllow=any` (lo crea `client-setup.sh`) |
| Los usuarios nuevos no aparecen en el cliente | No se regeneraron los mapas | `sudo make -C /var/yp` en el servidor |
| `ypserv` no responde desde la red | securenets con otra subred o máscara (p. ej. /24 en vez de /28) | Revisar `SUBRED_NET`/`SUBRED_MASK` y volver a correr `install.sh` |
| `rpcinfo` muestra puertos al azar | `YPSERVARGS`/`YPPASSWDDARGS` no aplicados | Revisar `/etc/default/nis` y `sudo systemctl restart ypserv yppasswdd` |
| `install.sh` se detiene con "ya existe con otro UID" | El usuario se creó a mano antes con otro UID | Borrarlo (`userdel`) o corregir el UID con `usermod -u` y repetir |
| **(Real, 2026-11-20)** `install.sh` mostraba la ayuda de `useradd` y no creaba ningún usuario | La primera versión llamaba `useradd "${args[@]}"` sin el nombre de usuario; además leía `grupos.csv` cuando el archivo se llamaba `grupo.csv` | `useradd "${args[@]}" "$usuario"` y archivo renombrado a `config/grupos.csv` |
| **(Real)** Al correr `install.sh` por segunda vez se cortaba en el paso 3 sin mensaje | `[[ -n "$extras" ]] && usermod …` devuelve 1 si no hay grupos extra, y con `set -e` + `pipefail` el bucle aborta el script | Cambiado a `if [[ -n "$extras" ]]; then …; fi`. Probado: dos ejecuciones seguidas terminan con código 0 |
| **(Real)** `E: Could not get lock /var/lib/dpkg/lock-frontend … (unattended-upgr)` y `debconf: config.dat is locked` | Recién encendida la VM con internet, `unattended-upgrades` estaba instalando actualizaciones | Los scripts esperan a que se liberen dpkg/debconf (`fuser`, hasta 10 min) y `apt-get -o DPkg::Lock::Timeout=600` |
| **(Real)** `id admin.ti` en el cliente mostraba solo `groups=3001(ti)`, aunque `getent group icpet` sí lo lista | El paquete `nis` instala `nscd` como dependencia, y su caché de grupos devuelve los grupos secundarios incompletos (sin `nscd`, `id` da `3001,3002,3003`) | `client-setup.sh` pone `enable-cache group no` en `/etc/nscd.conf` (respaldo en `nscd.conf.orig`) y reinicia `nscd` |
| **(Real)** El primer login SSH de `lab.icpet1` decía `Could not chdir to home directory /home/nis/lab.icpet1` | La autenticación NIS ya funcionaba, pero los homes aún no estaban montados por NFS | Configurar NFS en el cliente (`codigo/nfs/client-setup.sh`); después `pwd` = `/home/nis/lab.icpet1` |

Resultado en `srv-ecopetrol` + `cli-icpet` (2026-11-20): `verify.sh server` 9/9 y `verify.sh client` 12/12 (incluye login SSH real y contraseña incorrecta rechazada).
