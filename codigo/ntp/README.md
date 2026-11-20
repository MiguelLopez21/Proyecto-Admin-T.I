# NTP: servidor de hora de la red Ecopetrol (chrony)

## 1. Servicio y responsable

Servidor NTP con **chrony** que sincroniza el reloj de `srv-ecopetrol` con servidores públicos y sirve esa hora a los equipos de la red de la oficina. Así los registros de todos los servicios coinciden, y NIS, Samba y los certificados no fallan por diferencias de hora. Ver la justificación en [`analisis.md`](../../analisis.md).

Responsable: B (Web, BD y NTP).

## 2. Tipo

**Tipo D (Docker).** Imagen propia sobre `alpine:3.20` con el paquete `chrony` (4.5).

| Archivo | Para qué sirve |
|---|---|
| `Dockerfile` | Imagen sobre `alpine:3.20` con `chrony` y `tzdata`, y healthcheck con `chronyc tracking` |
| `config/chrony.conf.template` | Plantilla de la configuración (fuentes, `makestep`, `allow`, `local stratum 10`) |
| `entrypoint.sh` | Genera una línea `allow` por cada subred de `ALLOW_SUBNET` y arranca `chronyd -d` en primer plano |
| `docker-compose.yml` | Servicio `ntp`, puerto 123/UDP, `cap_add: SYS_TIME`, volumen `ntp_drift` |
| `.env.example` | Variables de ejemplo |
| `verify.sh` | Comprobaciones `server` y `client` |

## 3. Puertos y protocolos

| Puerto | Protocolo | Uso |
|---|---|---|
| 123 | UDP | NTP (clientes de la red) |

## 4. Variables

| Variable | Ejemplo | Significado |
|---|---|---|
| `ALLOW_SUBNET` | `172.20.10.0/28` | Subred(es) a las que se les sirve hora. Varias, separadas por coma (`172.20.10.0/28,192.168.1.0/24`). **Obligatoria**: sin `allow`, chrony no responde a los clientes |
| `AJUSTAR_RELOJ` | `true` | `true`: chrony ajusta el reloj del host. `false`: solo sirve hora sin tocar el reloj (útil para probar en un equipo que no es el servidor) |
| `TZ` | `America/Bogota` | Zona horaria de los logs del contenedor |

## 5. Datos persistentes

| Volumen | Ruta en el contenedor | Contenido |
|---|---|---|
| `ntp_drift` | `/var/lib/chrony` | `chrony.drift`: la deriva medida del reloj, para que tras un reinicio sincronice más rápido. Dueño `chrony` |

### Decisiones de configuración

- **`cap_add: SYS_TIME`**: el contenedor comparte el kernel con el host, así que chrony corrige el reloj **de todo el servidor**. Por eso el NTP del host está desactivado (`timedatectl set-ntp false`): dos procesos ajustando el mismo reloj se pelean.
- **`makestep 1.0 3`**: si al arrancar el reloj está desfasado más de 1 s, lo corrige de un salto; después lo ajusta de forma gradual. En la primera prueba el servidor estaba 5 s adelantado y chrony lo corrigió en 10 s.
- **`local stratum 10`**: si no hay internet en la demo, el servidor sigue sirviendo su propio reloj. Los clientes se mantienen sincronizados **entre sí y con el servidor**, aunque no con la hora oficial. El estrato 10 es alto a propósito, para que cualquier cliente con una fuente real la prefiera.
- **Sin `rtcsync`**: dentro de un contenedor no hay acceso al reloj de hardware.

## 6. Despliegue para A

1. Dokploy → proyecto `Ecopetrol-TI` → **Create Service → Compose**.
2. Tipo **Docker Compose** (no *Stack*: Swarm ignora `cap_add` y chrony fallaría con `adjtimex ... Operation not permitted`).
3. Provider **Git/GitHub** → repositorio del proyecto → branch `main` → Compose Path `./codigo/ntp/docker-compose.yml`.
4. **Environment**:
   ```
   ALLOW_SUBNET=172.20.10.0/28
   AJUSTAR_RELOJ=true
   TZ=America/Bogota
   ```
5. **Deploy**. En la pestaña *Logs* debe salir `Selected source ...` y, si el reloj estaba desfasado, `System clock was stepped by ...`.

Antes de desplegar, en el servidor:
```bash
sudo ss -ulpn | grep ':123 '        # no debe salir nada
timedatectl | grep 'NTP service'    # inactive
```

Probar sin Dokploy (en una VM Linux con Docker):
```bash
cd codigo/ntp
cp .env.example .env
docker compose up -d --build
docker compose logs -f ntp
```

## 7. Configuración del cliente

Reemplazar `SERVER_IP` por `172.20.10.14`.

**Linux con chrony** (cliente `cli-icpet`):
```bash
sudo apt install -y chrony
sudo sed -i 's/^pool /#pool /' /etc/chrony/chrony.conf
echo 'server SERVER_IP iburst prefer' | sudo tee /etc/chrony/sources.d/ecopetrol.sources
sudo systemctl restart chrony
chronyc sources          # la línea de SERVER_IP empieza con ^*
```

**Linux con systemd-timesyncd**: en `/etc/systemd/timesyncd.conf` poner `NTP=SERVER_IP`, luego `sudo systemctl restart systemd-timesyncd` y `timedatectl timesync-status` → `Server: SERVER_IP`.

**Windows** (PowerShell como administrador):
```powershell
net start w32time
w32tm /config /manualpeerlist:SERVER_IP /syncfromflags:manual /reliable:no /update
w32tm /resync
w32tm /query /source                                  # SERVER_IP
w32tm /stripchart /computer:SERVER_IP /samples:5      # desfases de pocos milisegundos
```
Para volver a la configuración de Windows: `w32tm /config /manualpeerlist:time.windows.com /syncfromflags:manual /update`.

## 8. Verificación

```bash
bash codigo/ntp/verify.sh server              # en el servidor
bash codigo/ntp/verify.sh client SERVER_IP    # en el cliente Linux
```

Salida esperada en el servidor:
```
[OK]    contenedor ntp corriendo (...)
[OK]    chronyc tracking: Leap status Normal (...)
[OK]    chronyc sources: hay una fuente seleccionada (^*)
[OK]    chrony.conf tiene allow: 172.20.10.0/28
[OK]    puerto 123/udp escuchando
[OK]    NTP del host desactivado (chrony del contenedor es la única autoridad)
```

Comandos útiles: `docker exec <ntp> chronyc tracking`, `chronyc sources -v`, `chronyc clients` (lista los clientes que han consultado).

## 9. Problemas conocidos y solución

| Síntoma | Causa | Solución |
|---|---|---|
| El cliente dice "no server suitable" o `w32tm` da timeout | Falta `allow` o la subred no incluye al cliente | Revisar `ALLOW_SUBNET` (ojo: la red de la demo es **/28**) |
| `adjtimex(0x8001) failed: Operation not permitted` | Falta `SYS_TIME`, o la app se creó como *Stack* | `cap_add: SYS_TIME` y app tipo **Docker Compose** |
| `bind: address already in use` en 123 | Otro NTP en el host | `sudo timedatectl set-ntp false`; desinstalar `ntp`/`chrony` del host |
| El cliente nunca llega a `^*` | Sin internet en el servidor o firewall bloqueando 123/UDP | `local stratum 10` sigue sirviendo hora; revisar UFW / cadena `DOCKER-USER` |
| `chronyc tracking` muestra `Reference ID 7F7F0101` y estrato 10 justo al arrancar | Mientras no ha validado ninguna fuente, chrony usa su reloj local (`local stratum 10`) | Esperar uno o dos sondeos (64 s cada uno) |
