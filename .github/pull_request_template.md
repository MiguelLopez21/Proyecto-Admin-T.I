## Servicio / cambio

<!-- Qué servicio entrega este PR (web, ntp, nis-nfs, samba-cups, docs) y un resumen corto. -->

## Contrato de entrega (00_COMUN §5)

### Si es tipo D (Docker: web, ntp, samba, cups)
- [ ] Imágenes base con versión fija (nada de `:latest` ni sin tag)
- [ ] **Sin** `container_name:`
- [ ] Puertos exactamente los de la tabla §3.2 (la web no publica puertos)
- [ ] Solo rutas relativas a su carpeta; datos persistentes en **volúmenes con nombre**
- [ ] Secretos por `${VARIABLE}` y declarados en `.env.example` con valor falso
- [ ] `restart: unless-stopped` en todos los servicios
- [ ] Logs a stdout/stderr (proceso en primer plano)
- [ ] `dokploy-network` como `external: true` solo si hace falta (web)
- [ ] Probado con `docker compose up -d --build` en una VM Linux

### Si es tipo H (host: nis, nfs)
- [ ] `#!/usr/bin/env bash` + `set -euo pipefail`
- [ ] Valida que corre como root y lee variables del `.env` pasado como argumento
- [ ] Idempotente (se corrió 2 veces sin errores ni duplicados)
- [ ] No pide nada interactivo y registra cada paso en pantalla
- [ ] Probado en una VM Ubuntu 24.04 limpia

### Siempre
- [ ] `README.md` con los 9 puntos de la plantilla §5.3
- [ ] `verify.sh server` y `verify.sh client` imprimen `OK`/`FALLA` y salen con 0 solo si todo pasa
- [ ] `bash -n codigo/<servicio>/*.sh` sin errores
- [ ] `docker compose -f codigo/<servicio>/docker-compose.yml config` sin errores (tipo D)
- [ ] Capturas de la prueba local en `capturas/<servicio>/NN_descripcion.png` (sin contraseñas ni tokens)
- [ ] Ningún secreto, `.env`, `.key` ni `.pem` en el diff

## Cómo lo probé

<!-- Comandos y salida relevante, o enlace a las capturas. -->
