# Samba: carpeta compartida de la oficina Bogotá (Ecopetrol)

Servidor SMB en un contenedor Alpine 3.20 que publica el recurso `administrativa` para Windows, macOS y Linux. Sin invitados y sin SMB1.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `Dockerfile` | Imagen sobre `alpine:3.20` con `samba`, `samba-common-tools`, `tini` y `bash` |
| `config/smb.conf` | Configuración de Samba (recurso `[administrativa]`) |
| `entrypoint.sh` | Crea grupo y usuarios, asigna claves, valida con `testparm` y arranca `smbd` |
| `docker-compose.yml` | Servicio `samba`, puerto 445, volúmenes `samba_data` y `samba_state` |
| `.env.example` | Variables de ejemplo (copiar a `.env`) |
| `verify.sh` | Comprobaciones `server` y `client` |

## Variables de entorno

| Variable | Ejemplo | Descripción |
|---|---|---|
| `SMB_GROUP` | `administrativa` | Grupo dueño del recurso |
| `SMB_GID` | `3003` | GID del grupo (igual que en NIS) |
| `SMB_USERS` | `fin.bogota:2021,rrhh.bogota:2022,admin.ti:2001` | Lista `usuario:uid` (mismos UID que en NIS) |
| `SMB_PASSWORD` | `cambiar` | Clave inicial de todos los usuarios. **Cambiarla; no se sube al repositorio** |

`lab.icpet1` no está en `SMB_USERS` a propósito: es el usuario de la prueba negativa.

## Requisitos del servidor

- Una máquina o VM **Linux** con Docker. Docker Desktop en Windows no sirve: Windows ya usa el puerto 445.
- Que el puerto 445 esté libre. Si el host tiene el paquete `samba` instalado, `smbd` lo ocupa y el contenedor falla con `bind failed on port 445`.

## Probar en local

```bash
cd codigo/samba
cp .env.example .env          # editar SMB_PASSWORD
docker compose up -d --build
docker compose logs -f samba
bash verify.sh server
```

## Desplegar en Dokploy

1. Servicio tipo **Compose**, repositorio del proyecto, *Compose Path* `./codigo/samba/docker-compose.yml`.
2. Pestaña *Environment*: pegar `SMB_GROUP`, `SMB_GID`, `SMB_USERS` y `SMB_PASSWORD` con la clave real.
3. Deploy. Los logs salen por stdout en la pestaña *Logs*.

## Conectar desde los clientes

Reemplazar `SERVER_IP` por la IP del servidor.

- **Windows:** Explorador de archivos → `\\SERVER_IP\administrativa`, o
  `net use Z: \\SERVER_IP\administrativa /user:ECOPETROL\fin.bogota *`.
  Para cambiar de usuario: `net use * /delete` (Windows guarda en caché la primera credencial).
- **macOS:** Finder → Cmd+K → `smb://SERVER_IP/administrativa`.
- **Linux:** `smbclient //SERVER_IP/administrativa -U fin.bogota`, o montarlo con `cifs-utils`.

## Verificación

```bash
# En el servidor
bash verify.sh server

# Desde un cliente Linux con smbclient
read -rs -p "Clave de prueba: " SMB_PASSWORD; export SMB_PASSWORD; echo
bash verify.sh client SERVER_IP
```

Resultado esperado: todas las líneas `[OK]` y código de salida 0. `lab.icpet1` y el acceso sin usuario deben dar `NT_STATUS_LOGON_FAILURE` o `ACCESS_DENIED`.

## Problemas típicos

| Síntoma | Causa | Solución |
|---|---|---|
| `bind failed on port 445` | `smbd` instalado en el host, o se está usando Windows | Usar VM Linux; desinstalar el paquete `samba` del host |
| Windows: error 1272, acceso de invitado bloqueado | Se intentó entrar como invitado | Conectar con usuario y clave |
| Windows: error 1219, varias conexiones | Credencial en caché | `net use * /delete` |
| Error al escribir | Permisos de la carpeta o `force group` | `2770` + `force group = administrativa` |
| Claves perdidas tras redeploy | Falta el volumen `samba_state` | Mantener el volumen; igual el entrypoint las recrea |

## Seguridad

Sin invitados (`map to guest = never`), SMB1 desactivado (`server min protocol = SMB2_10`), firma y cifrado negociados, usuarios sin shell y sin secretos en el repositorio.
