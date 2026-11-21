# NFS: archivos compartidos para Linux (NFSv4)

## 1. Servicio y responsable

Servidor **NFSv4** en `srv-ecopetrol` con dos recursos: la carpeta de trabajo de los laboratorios del Icpet (`/srv/nfs/ecopetrol`), accesible solo para el grupo `icpet`, y los homes de los usuarios NIS (`/home/nis`), para que cada usuario encuentre sus archivos en cualquier equipo Linux de la red. Los permisos funcionan porque NIS da los mismos UID y GID en el servidor y en los clientes. Ver la justificación en [`analisis.md`](../../analisis.md).

Responsable: C (NIS + NFS).

## 2. Tipo

**Tipo H (host).** Corre en Ubuntu 24.04, no en Docker, porque usa `nfsd` del kernel. Paquetes: `nfs-kernel-server` (servidor) y `nfs-common` (cliente).

| Archivo | Para qué sirve |
|---|---|
| `install.sh` | Servidor: comprueba NIS, crea las carpetas con sus permisos, escribe `/etc/exports` e `idmapd.conf` |
| `client-setup.sh` | Cliente: `idmapd.conf`, puntos de montaje y `/etc/fstab` |
| `.env.example` | Variables de ejemplo |
| `verify.sh` | Comprobaciones `server` y `client` |

## 3. Puertos y protocolos

| Puerto | Protocolo | Uso |
|---|---|---|
| 2049 | TCP | NFSv4 (un único puerto, sin `mountd`) |

Los clientes montan con `nfs4`. NFSv3 queda habilitado por defecto en el paquete pero no se usa; si se quiere cerrar, `[nfsd] vers3=n` en `/etc/nfs.conf`.

## 4. Variables

| Variable | Ejemplo | Significado |
|---|---|---|
| `SERVER_IP` | `172.20.10.14` | IP del servidor NFS (la usa el cliente en `/etc/fstab`) |
| `SUBRED` | `172.20.10.0/28` | Red a la que se exporta. La demo usa una **/28**, no una /24 |
| `NFS_DOMAIN` | `ecopetrol.local` | `Domain` de `/etc/idmapd.conf`; debe ser igual en servidor y cliente |

## 5. Datos persistentes

| Ruta (servidor) | Permisos | Contenido |
|---|---|---|
| `/srv/nfs/ecopetrol` | `2770 root:icpet` | Carpeta del Icpet. El bit setgid hace que todo lo nuevo herede el grupo `icpet` |
| `/srv/nfs/ecopetrol/ensayos` | `2770 root:icpet` | Subcarpeta de ejemplo |
| `/home/nis/<usuario>` | `700 <usuario>` | Homes de los usuarios NIS |

`/etc/exports`:

```
/srv/nfs/ecopetrol  172.20.10.0/28(rw,sync,no_subtree_check,root_squash)
/home/nis           172.20.10.0/28(rw,sync,no_subtree_check,root_squash)
```

**`root_squash` y no `no_root_squash`** (que trae la guía del enunciado): con `no_root_squash`, el root de cualquier equipo de la red sería root sobre los archivos del servidor. Con `root_squash`, el root del cliente se convierte en `nobody` y no puede entrar a la carpeta del Icpet.

En el cliente se monta en `/mnt/ecopetrol` y `/home/nis` (nunca sobre `/home`, que ocultaría los homes locales).

## 6. Despliegue para A

Requiere NIS ya instalado en el servidor (`codigo/nis/README.md`). En `srv-ecopetrol`, desde la raíz del repositorio:

1. `cp codigo/nfs/.env.example codigo/nfs/.env`
2. `sudo bash codigo/nfs/install.sh codigo/nfs/.env`
3. Al terminar imprime `exportfs -v` con los dos exports.
4. `sudo bash codigo/nfs/verify.sh server` → todo `[OK]`.
5. El puerto 2049/tcp va en `PUERTOS_HOST` de `codigo/servidor/ufw.sh` (ver el README de NIS).

## 7. Configuración del cliente (Linux, `cli-icpet`)

1. Primero NIS en el cliente (`codigo/nis/client-setup.sh`): el script de NFS se detiene si no encuentra al usuario `lab.icpet1`.
2. Copiar `codigo/nfs/` al cliente, crear su `.env` y ejecutar `sudo bash client-setup.sh .env`.
3. Las líneas de `/etc/fstab` llevan `_netdev`, así que se montan solas al arrancar cuando la red está lista.

## 8. Verificación

```bash
# Servidor
sudo bash verify.sh server
#   nfs-server activo, 2 exports con root_squash, 2049/tcp, /srv/nfs/ecopetrol 2770 root:icpet, idmapd

# Cliente
sudo bash verify.sh client 172.20.10.14
#   2 montajes nfs4, lab.icpet1 crea un archivo (dueño lab.icpet1:icpet), lab.icpet2 lo modifica,
#   fin.bogota recibe Permission denied, root del cliente no escribe (root_squash),
#   el home de lab.icpet1 es privado. Borra el archivo de prueba al terminar.
```

| Acción en el cliente | Resultado esperado |
|---|---|
| `lab.icpet1` crea un archivo en `/mnt/ecopetrol/ensayos` | OK; grupo `icpet`, por setgid |
| `lab.icpet2` lo lee o modifica | OK, porque es del mismo grupo |
| `fin.bogota` hace `ls /mnt/ecopetrol` | `Permission denied` |
| `root` del cliente crea un archivo en `/mnt/ecopetrol` | `Permission denied`, por `root_squash` |
| `lab.icpet1` entra por SSH | Su home `/home/nis/lab.icpet1` está servido por NFS |

Capturas mínimas: `capturas/nfs/01_exportfs-v`, `02_cliente-findmnt`, `03_permisos-grupo-icpet`, `04_fin.bogota-denegado`, `05_root-squash`.

## 9. Problemas conocidos y solución

| Síntoma | Causa | Solución |
|---|---|---|
| Los archivos aparecen como `nobody:nogroup` | `Domain` distinto en `idmapd.conf`, o UIDs distintos en cliente y servidor | El mismo `NFS_DOMAIN` en los dos lados; UIDs siempre desde NIS |
| `mount.nfs4: access denied by server` | La subred del export no incluye al cliente (p. ej. una /24 que no corresponde) | Revisar `SUBRED`, `/etc/exports` y `sudo exportfs -ra` |
| El arranque del cliente se queda esperando el montaje | Servidor apagado o falta `_netdev` | Encender primero el servidor; `_netdev` ya está en el `fstab` |
| `Permission denied` para un usuario válido | Falta setgid o el grupo está mal | `chmod 2770` y `chgrp icpet` (lo hace `install.sh`) |
| `install.sh` dice "Falta NIS" | El grupo `icpet` (3002) no existe en el servidor | Ejecutar antes `codigo/nis/install.sh` |
| `admin.ti` recibe `Permission denied` en `/mnt/ecopetrol` aunque está en `icpet` | La caché de grupos de `nscd` en el cliente oculta sus grupos secundarios (ver README de NIS) | `client-setup.sh` de NIS desactiva esa caché; comprobar con `id admin.ti` |
| `ls: cannot access '/srv/nfs/ecopetrol/ensayos': Permission denied` como `sysadmin` en el servidor | Es lo esperado: `sysadmin` no está en `icpet` y la carpeta es `2770` | Revisar con `sudo` o como un usuario del grupo |

Resultado en `srv-ecopetrol` + `cli-icpet` (2026-11-20): `verify.sh server` 7/7 y `verify.sh client` 9/9.
