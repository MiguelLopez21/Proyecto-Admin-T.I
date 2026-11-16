// Ecopetrol TI — carga de datos desde la API (/api/*) y renderizado. Sin dependencias.
(function () {
  'use strict';

  const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));

  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  const fechaLarga = (iso) => {
    if (!iso) return '';
    const [a, m, d] = iso.split('-').map(Number);
    return `${d} de ${meses[m - 1]} de ${a}`;
  };

  async function api(ruta) {
    const r = await fetch(ruta, { headers: { Accept: 'application/json' } });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  }

  function errorEn(el, err) {
    el.innerHTML = `<p class="error-carga">No se pudieron cargar los datos (${esc(err.message)}). Intente de nuevo más tarde.</p>`;
  }

  // Marca el enlace de la página actual en el menú
  const actual = location.pathname.replace(/\.html$/, '').replace(/\/$/, '') || '/';
  document.querySelectorAll('.menu a').forEach((a) => {
    const ruta = a.getAttribute('href').replace(/\.html$/, '') || '/';
    if (ruta === actual || (ruta === '/' && actual === '/index')) a.setAttribute('aria-current', 'page');
  });

  // Estado del sistema (pie de página): /api/health
  const estado = document.getElementById('estado');
  if (estado) {
    api('/api/health')
      .then((h) => {
        const ok = h.db === 'ok';
        estado.innerHTML = `<span class="punto ${ok ? 'ok' : 'error'}"></span> Sistema ${ok ? 'en línea' : 'con fallas'} · base de datos ${ok ? 'conectada' : 'sin conexión'}`;
      })
      .catch(() => { estado.innerHTML = '<span class="punto error"></span> API sin respuesta'; });
  }

  // Sedes
  const sedes = document.getElementById('sedes');
  if (sedes) {
    api('/api/sedes')
      .then((lista) => {
        if (!lista.length) { sedes.innerHTML = '<p class="vacio">No hay sedes registradas.</p>'; return; }
        const clase = { 'refinería': 'refineria', instituto: 'instituto', filial: 'filial' };
        sedes.innerHTML = lista.map((s) => `
          <article class="tarjeta">
            <span class="etiqueta ${clase[s.tipo] || ''}">${esc(s.tipo)}</span>
            <h3>${esc(s.nombre)}</h3>
            <p class="meta">${esc(s.ciudad)}, ${esc(s.departamento)}</p>
            <p>${esc(s.descripcion)}</p>
          </article>`).join('');
      })
      .catch((e) => errorEn(sedes, e));
  }

  // Noticias (lista completa o resumen en la portada)
  document.querySelectorAll('[data-noticias]').forEach((cont) => {
    const limite = Number(cont.dataset.noticias) || 10;
    api(`/api/noticias?limit=${limite}`)
      .then((lista) => {
        if (!lista.length) { cont.innerHTML = '<p class="vacio">No hay noticias.</p>'; return; }
        cont.innerHTML = lista.map((n) => `
          <article class="tarjeta noticia">
            <time datetime="${esc(n.fecha)}">${esc(fechaLarga(n.fecha))}</time>
            <h3>${esc(n.titulo)}</h3>
            <p>${esc(n.resumen)}</p>
            ${n.fuente_url ? `<a href="${esc(n.fuente_url)}" target="_blank" rel="noopener noreferrer">Ver fuente ↗</a>` : ''}
          </article>`).join('');
      })
      .catch((e) => errorEn(cont, e));
  });

  // Portal TI
  const servicios = document.getElementById('servicios');
  if (servicios) {
    const iconos = ['🌐', '📁', '🖨️', '🕒', '🧪', '👤'];
    api('/api/servicios-ti')
      .then((lista) => {
        servicios.innerHTML = lista.map((s, i) => `
          <article class="tarjeta servicio">
            <div class="icono" aria-hidden="true">${iconos[i] || '⚙️'}</div>
            <h3>${esc(s.nombre)}</h3>
            <p class="meta">${esc(s.protocolo)} · puerto <code>${esc(s.puerto)}</code></p>
            <p class="como">${esc(s.como_conectar)}</p>
          </article>`).join('');
      })
      .catch((e) => errorEn(servicios, e));
  }
})();
