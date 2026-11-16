-- Datos semilla. Idempotente (ON CONFLICT DO NOTHING).
-- Fuentes: docs/design/proyecto-final-ecopetrol/research.md §5 y §9.
-- En servicios_ti, {SERVER_IP} y {DOMINIO} los reemplaza la API con sus variables de entorno.

INSERT INTO sedes (nombre, ciudad, departamento, tipo, descripcion) VALUES
  ('Sede corporativa', 'Bogotá', 'Cundinamarca', 'corporativa',
   'Oficinas administrativas en la Carrera 13 No. 36-24. Aquí trabaja el personal de finanzas, recursos humanos y TI que usa la carpeta compartida y la impresora de la oficina.'),
  ('Refinería de Barrancabermeja', 'Barrancabermeja', 'Santander', 'refinería',
   'Refinería operada directamente por Ecopetrol S.A., la más grande del país.'),
  ('Refinería de Cartagena (Reficar)', 'Cartagena', 'Bolívar', 'refinería',
   'Refinería de Cartagena S.A.S., 100 % propiedad de Ecopetrol.'),
  ('Icpet', 'Piedecuesta', 'Santander', 'instituto',
   'Instituto Colombiano del Petróleo y Energías de la Transición (antes ICP, renombrado en 2024): 30 hectáreas, 34 plantas piloto y 29 laboratorios.'),
  ('Cenit', 'Bogotá', 'Cundinamarca', 'filial',
   'Filial de transporte y logística de hidrocarburos; maneja cerca del 45 % de la capacidad de oleoductos del país.')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO noticias (titulo, resumen, fecha, fuente_url) VALUES
  ('Ecopetrol cerró 2025 con una producción de 745.300 barriles equivalentes por día',
   'El grupo reportó una producción promedio de 745.300 bpe/d en 2025, con 517.000 barriles diarios de crudo nacional.',
   '2026-03-04',
   'https://www.infobae.com/colombia/2026/03/04/ecopetrol-reporto-caida-en-las-utilidades-informo-de-cuanto-fue-la-produccion-de-petroleo-en-2025-y-hasta-cuando-habra-gas/'),
  ('Joaquín Gutiérrez Caballero, nuevo presidente de Ecopetrol',
   'La Junta Directiva eligió el 24 de septiembre de 2026 a Joaquín Gutiérrez Caballero como presidente de la compañía.',
   '2026-09-24',
   'https://www.larepublica.co/economia/junta-directiva-de-ecopetrol-escogio-a-joaquin-gutierrez-como-presidente-4489623'),
  ('Estrategia 2040: "Energía que Transforma"',
   'La estrategia aprobada en diciembre de 2021 busca crecer con la transición energética, generar valor con SosTECnibilidad, lograr retornos competitivos y desarrollar conocimiento de vanguardia.',
   '2021-12-01',
   'https://files.ecopetrol.com.co/web/esp/cargas/web/noticias/VCM/estrategia-2040.pdf'),
  ('El ICP se transforma en Icpet, centro de la transición energética',
   'El Instituto Colombiano del Petróleo pasó a llamarse Icpet (Instituto Colombiano del Petróleo y Energías de la Transición), con sede en Piedecuesta, Santander.',
   '2024-07-31',
   'https://www.vanguardia.com/economia/local/2024/07/31/santander-el-corazon-de-la-transicion-con-el-icpet/'),
  ('Ciberataque al grupo Ecopetrol comprometió información de 3.300 cuentas',
   'En julio de 2026 la empresa confirmó un acceso ilegal que afectó archivos asociados a unas 3.300 cuentas de 15 empresas del grupo. Refuerza la importancia de la autenticación centralizada y de registros con hora sincronizada.',
   '2026-07-18',
   'https://www.vanguardia.com/economia/2026/07/18/ciberataque-a-ecopetrol-15-empresas-del-grupo-empresarial-estan-afectadas/')
ON CONFLICT (titulo) DO NOTHING;

INSERT INTO servicios_ti (nombre, protocolo, puerto, como_conectar) VALUES
  ('Sitio web y portal', 'HTTPS', '443',
   'Abrir https://www.{DOMINIO}. Si el navegador muestra advertencia, importar la CA del laboratorio (ca.crt) que entrega TI.'),
  ('Carpeta compartida (Samba)', 'SMB', '445',
   'Windows: Explorador → \{SERVER_IP}\administrativa (usuario ECOPETROL\<su usuario>). macOS: Finder → Cmd+K → smb://{SERVER_IP}/administrativa.'),
  ('Impresora de la oficina (CUPS)', 'IPP', '631',
   'Agregar la impresora http://{SERVER_IP}:631/printers/Ecopetrol-Bogota-PDF con el controlador Microsoft PS Class Driver. Los trabajos se guardan como PDF.'),
  ('Hora de la red (NTP)', 'NTP', '123/UDP',
   'Windows (admin): w32tm /config /manualpeerlist:{SERVER_IP} /syncfromflags:manual /update y luego w32tm /resync. Linux: server {SERVER_IP} iburst en chrony.'),
  ('Carpeta de laboratorio (NFS)', 'NFSv4', '2049',
   'Solo equipos Linux del Icpet: sudo mount -t nfs4 {SERVER_IP}:/srv/nfs/ecopetrol /mnt/ecopetrol (grupo icpet).'),
  ('Cuentas de red (NIS)', 'RPC', '111, 834, 835',
   'Equipos Linux unidos al dominio NIS ecopetrol.local: inician sesión con su usuario de red. Cambio de contraseña con yppasswd.')
ON CONFLICT (nombre) DO NOTHING;
