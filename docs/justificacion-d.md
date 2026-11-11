# Justificación de Samba y CUPS (para `analisis.md`)

## Samba: compartición de archivos para Windows y macOS

**Necesidad.** La sede corporativa de Ecopetrol en Bogotá concentra al personal administrativo. Ese personal necesita una carpeta común donde guardar y compartir documentos con control de acceso. Samba implementa el protocolo SMB, el que usan de forma nativa Windows y macOS, de modo que no hace falta instalar software en los clientes. (Que el personal administrativo use Windows o Mac no tiene fuente pública; es un supuesto del escenario.)

**Por qué es adecuado.**
- Acceso desde el Explorador de Windows y el Finder sin agentes adicionales.
- Autenticación por usuario y grupo: solo el grupo `administrativa` accede al recurso; no se permiten invitados.
- Seguridad actual: SMB1 desactivado y firma SMB negociada, como exige Windows 11 24H2.
- Contexto de seguridad: el incidente de julio de 2026 comprometió cuentas de usuario, lo que refuerza el control de acceso por usuario y grupo y la ausencia de acceso anónimo.

**Complementa a NFS.** NFS sirve a clientes Linux; Samba sirve a Windows/Mac. Los UID y GID coinciden con los de NIS (grupo `administrativa` 3003), así que los dueños de los archivos son coherentes entre servicios.

## CUPS: servidor de impresión

**Necesidad.** Una sede administrativa necesita imprimir de forma centralizada, con una cola única, control de quién administra y sin instalar un driver distinto en cada equipo. (La necesidad de impresión no tiene fuente pública; es un supuesto del escenario.)

**Por qué es adecuado.**
- CUPS es el estándar de impresión en Linux y habla IPP, compatible con Windows, macOS y Linux.
- Una sola cola compartida con administración restringida al grupo `lpadmin` y acceso limitado a la subred de la oficina.
- Como no hay impresora física, se usa una impresora virtual PDF que demuestra la cola completa (envío, cola, procesamiento y salida). Si se consigue una impresora real, se agrega con su URI.

## Despliegue

Ambos servicios se entregan como contenedores Docker construidos sobre imágenes oficiales con versión fija (`alpine:3.20` y `debian:12-slim`) y se despliegan con Dokploy como Compose.

## Requisitos (filas para la tabla de `analisis.md`)

| Servicio | IP | Puerto | Protocolo | Tipo de servicio |
|---|---|---|---|---|
| Samba | IP fija del servidor | 445 | TCP (SMB 2/3) | Archivos para Windows/Mac (Docker) |
| CUPS | IP fija del servidor | 631 | TCP (IPP/HTTP/HTTPS) | Impresión (Docker) |
