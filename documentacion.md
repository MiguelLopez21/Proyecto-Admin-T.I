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

_Pendiente (A)._

## 2. Dokploy (A)

_Pendiente (A)._

## 3. DNS y HTTPS (A)

_Pendiente (A)._

## 4. NTP (B)

### Objetivo
_Pendiente (B)._
### Instalación (comandos)
### Verificación (comando y salida esperada)
### Capturas
### Problemas encontrados

## 5. Base de datos (B)

### Objetivo
_Pendiente (B)._
### Instalación (comandos)
### Verificación (comando y salida esperada)
### Capturas
### Problemas encontrados

## 6. Web (B)

### Objetivo
_Pendiente (B)._
### Instalación (comandos)
### Verificación (comando y salida esperada)
### Capturas
### Problemas encontrados

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

_Pendiente (A)._

## 12. Extras

_Pendiente: backup automático, monitoreo, UFW, Docker Compose multi-contenedor._

## 13. Problemas generales

_Pendiente: problemas transversales (red bridged, certificado autofirmado, UID/GID entre servicios)._

## 14. Conclusiones

_Pendiente: resultados, lecciones aprendidas, análisis costo-beneficio._
