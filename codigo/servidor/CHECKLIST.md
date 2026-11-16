# Checklist de despliegue del servidor `srv-ecopetrol`

Orden probado para dejar el servidor listo desde cero. Cada paso tiene su verificación; no se pasa al siguiente si la verificación falla.

| Valor | Dato |
|---|---|
| SO | Ubuntu Server 24.04.5 LTS |
| VM | VirtualBox 7.2, **EFI**, 2 vCPU, 6 GB RAM, 40 GB disco, gráficos **VBoxVGA** |
| Red | Adaptador puente sobre la interfaz que use el equipo anfitrión en la demo |
| IP / subred / gateway | `172.20.10.14` / `172.20.10.0/28` / `172.20.10.1` |
| Dominio | `ecopetrol-ti.duckdns.org` (`www.` y `panel.` resuelven a la misma IP) |
| Usuario del SO | `sysadmin` (UID 1000). `admin.ti` **no** se crea aquí: lo crea el script NIS (UID 2001) |

## 1. Máquina virtual

- [ ] Crear la VM con **EFI activado** (con BIOS el instalador de 24.04 se queda colgado).
- [ ] Controlador gráfico **VBoxVGA** (con VMSVGA aparecen errores `vmwgfx` en consola).
- [ ] Red: **adaptador puente** sobre la interfaz que realmente usa el anfitrión (Wi-Fi o Ethernet). Si no coincide, la VM arranca sin IPv4.
- [ ] Instalar Ubuntu Server: hostname `srv-ecopetrol`, usuario `sysadmin`, marcar *Install OpenSSH server*, sin snaps.

Verificación: `hostnamectl` → `srv-ecopetrol`; `ip -br a` → la interfaz `enp0s3` tiene IPv4.

## 2. Preparación base

```bash
sudo bash preparar-servidor.sh     # apt full-upgrade, swap 2 GB, TZ America/Bogota, NTP del host OFF
sudo reboot                        # si el script lo pide
```

Verificación: `free -h` → Swap 2.0Gi; `timedatectl` → `America/Bogota` y `NTP service: inactive`.

- [ ] **Snapshot `00-base-limpia` con la VM APAGADA.** Nunca en caliente: bajo Hyper-V la VM se congela y queda *inaccessible*.

## 3. Dokploy

```bash
sudo ss -tulpn | grep -E ':(80|443|3000)\b'    # no debe salir nada
curl -sSL https://dokploy.com/install.sh | sudo sh
```

Verificación:
- `docker info --format '{{.Swarm.LocalNodeState}}'` → `active`
- `docker service ls` → `dokploy 1/1`, `dokploy-postgres 1/1`; `docker ps` → `dokploy-traefik` arriba
- `curl -I http://localhost:3000` → 200 o 307

- [ ] Crear el admin en `http://SERVER_IP:3000` y el proyecto **`Ecopetrol-TI`**.
- [ ] **Snapshot `01-dokploy`** (VM apagada).

## 4. IP fija

```bash
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo mv /etc/netplan/50-cloud-init.yaml /root/50-cloud-init.yaml.bak
sudo cp netplan-60-static.yaml.example /etc/netplan/60-static.yaml
sudo chmod 600 /etc/netplan/60-static.yaml
sudo netplan try                       # confirmar con Enter antes de 120 s
```

Verificación: `ip -br a show enp0s3` → `172.20.10.14/28`; `ip r` → `default via 172.20.10.1`; `ping -c2 1.1.1.1`.

- [ ] Si Swarm se inicializó con otra IP, revisar `docker node inspect self --format '{{.Status.Addr}}'` y que los servicios de Dokploy queden estables (`docker service ls`).

## 5. DNS (DuckDNS)

```bash
curl "https://www.duckdns.org/update?domains=ecopetrol-ti&token=<TOKEN>&ip=172.20.10.14&verbose=true"
```

El token **no** se guarda en el repositorio.

Verificación: `nslookup www.ecopetrol-ti.duckdns.org` → `172.20.10.14`. Si el router descarta respuestas con IP privada (*DNS rebinding*), usar `1.1.1.1` como DNS del cliente o el archivo `hosts`.

## 6. HTTPS con CA propia

```bash
bash generar-certificado.sh ecopetrol-ti.duckdns.org 172.20.10.14 ~/certs
```

- [ ] Dokploy → Settings → Certificates → Add: `fullchain.crt` + `servidor.key` (PKCS#8: `openssl pkey -in servidor.key`).
- [ ] Settings → Web Server → Server Domain: `panel.ecopetrol-ti.duckdns.org`, HTTPS on, Certificate Provider **None**.
- [ ] En cada aplicación web: dominio con HTTPS on y certificado **None** (Traefik elige el certificado por SNI).
- [ ] Clientes: importar `ca.crt` (Windows `certutil -addstore -f Root ca.crt`; Linux `/usr/local/share/ca-certificates/` + `update-ca-certificates`).

Verificación (sin `-k`):
```bash
curl -I --cacert ~/certs/ca.crt https://panel.ecopetrol-ti.duckdns.org     # HTTP/2 200
echo | openssl s_client -connect panel.ecopetrol-ti.duckdns.org:443 \
  -servername panel.ecopetrol-ti.duckdns.org -CAfile ~/certs/ca.crt 2>/dev/null | grep 'Verify return code'   # 0 (ok)
```

## 7. Servicios del equipo (en este orden)

| # | Servicio | Cómo | Verificación |
|---|---|---|---|
| 1 | NTP (B) | Compose tipo **Docker Compose** (no Stack), `./codigo/ntp/docker-compose.yml`, `ALLOW_SUBNET=172.20.10.0/28` | `bash codigo/ntp/verify.sh server` |
| 2 | PostgreSQL | Dokploy Database, sin *External Port* | conexión interna desde la web |
| 3 | Web (B) | Compose `./codigo/web/docker-compose.yml`, dominio `www.` con HTTPS y cert None | `curl -I https://www.ecopetrol-ti.duckdns.org` |
| 4 | NIS → NFS (C) | Scripts de host; **snapshot `02-host-services` antes** | `verify.sh server` de cada uno |
| 5 | Samba (D) | Compose `./codigo/samba/docker-compose.yml` | `bash codigo/samba/verify.sh server` |
| 6 | CUPS (D) | Compose `./codigo/cups/docker-compose.yml` | `bash codigo/cups/verify.sh server` |

Antes de cada despliegue: `sudo ss -tulpn` para confirmar que el puerto está libre, y `timedatectl` para confirmar que el NTP del host sigue inactivo.

## 8. Antes de la demo

- [ ] `sudo ss -tulpn` → solo los puertos de la tabla común (captura `servidor/09_ss-tulpn-puertos`).
- [ ] Todos los servicios `Running` en Dokploy (captura `dokploy/07_servicios-todos-running`).
- [ ] Exportar la VM a OVA y **snapshot `03-pre-demo`** (VM apagada).
