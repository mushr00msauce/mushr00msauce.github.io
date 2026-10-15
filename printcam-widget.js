/* Mushbox Printcam widget
   Usage:  <div id="mushbox-printcam"></div>
           <script src="/printcam-widget.js" defer></script>
   Add data-hide-when-idle to the div to hide it entirely unless a print is running
   (good for home.html). Without it, it shows an idle/offline card (printcam.html). */
(function () {
  'use strict';
  var API = 'https://printcam.themushbox.com';
  var STATUS_MS = 10000, FRAME_MS = 2000;
  var root = document.getElementById('mushbox-printcam');
  if (!root) return;
  var hideIdle = root.hasAttribute('data-hide-when-idle');

  var css = '' +
    '.mpc{--mpc-bg:#14110f;--mpc-card:#1e1a17;--mpc-line:#2e2823;--mpc-text:#f3ece4;--mpc-dim:#a89c90;' +
    '--mpc-amber:#f5a524;--mpc-live:#e5484d;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;' +
    'color:var(--mpc-text);background:var(--mpc-card);border:1px solid var(--mpc-line);border-radius:16px;' +
    'overflow:hidden;max-width:960px;margin:0 auto}' +
    '.mpc-head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px 18px;border-bottom:1px solid var(--mpc-line)}' +
    '.mpc-title{font-weight:700;font-size:1.05rem;letter-spacing:.01em;margin:0}' +
    '.mpc-badge{display:inline-flex;align-items:center;gap:6px;font-size:.75rem;font-weight:700;text-transform:uppercase;' +
    'letter-spacing:.08em;padding:4px 10px;border-radius:999px;background:var(--mpc-line);color:var(--mpc-dim)}' +
    '.mpc-badge i{width:8px;height:8px;border-radius:50%;background:currentColor;display:block}' +
    '.mpc[data-s=live] .mpc-badge{background:rgba(229,72,77,.15);color:var(--mpc-live)}' +
    '.mpc[data-s=live] .mpc-badge i{animation:mpcPulse 1.4s ease-in-out infinite}' +
    '.mpc[data-s=paused] .mpc-badge{background:rgba(245,165,36,.15);color:var(--mpc-amber)}' +
    '@keyframes mpcPulse{50%{opacity:.25}}' +
    '.mpc-view{position:relative;aspect-ratio:16/9;background:var(--mpc-bg);display:flex;align-items:center;justify-content:center}' +
    '.mpc-view img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;display:none}' +
    '.mpc-view img.on{display:block}' +
    '.mpc-msg{text-align:center;padding:24px;color:var(--mpc-dim);max-width:34ch;line-height:1.45}' +
    '.mpc-msg b{display:block;color:var(--mpc-text);font-size:1.1rem;margin-bottom:6px}' +
    '.mpc-shroom{font-size:2.4rem;display:block;margin-bottom:8px}' +
    '.mpc-info{padding:14px 18px 18px}' +
    '.mpc-job{font-weight:600;margin:0 0 10px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
    '.mpc-bar{height:8px;border-radius:999px;background:var(--mpc-line);overflow:hidden}' +
    '.mpc-bar span{display:block;height:100%;width:0;background:var(--mpc-amber);transition:width .8s ease}' +
    '.mpc-stats{display:flex;flex-wrap:wrap;gap:6px 18px;margin-top:10px;font-size:.88rem;color:var(--mpc-dim)}' +
    '.mpc-stats strong{color:var(--mpc-text);font-variant-numeric:tabular-nums}' +
    '.mpc[data-s=idle] .mpc-info,.mpc[data-s=offline] .mpc-info{display:none}';

  if (!document.getElementById('mpc-style')) {
    var st = document.createElement('style');
    st.id = 'mpc-style'; st.textContent = css;
    document.head.appendChild(st);
  }

  root.innerHTML =
    '<section class="mpc" data-s="idle" aria-live="polite">' +
      '<div class="mpc-head"><h2 class="mpc-title">Live from the Mushbox print bed</h2>' +
      '<span class="mpc-badge"><i></i><span class="mpc-badge-t">Idle</span></span></div>' +
      '<div class="mpc-view"><img alt="Live view of the 3D printer making Mushbox parts">' +
        '<div class="mpc-msg"></div></div>' +
      '<div class="mpc-info"><p class="mpc-job"></p><div class="mpc-bar"><span></span></div>' +
        '<div class="mpc-stats"></div></div>' +
    '</section>';

  var box = root.querySelector('.mpc'),
      img = root.querySelector('img'),
      msg = root.querySelector('.mpc-msg'),
      badge = root.querySelector('.mpc-badge-t'),
      job = root.querySelector('.mpc-job'),
      bar = root.querySelector('.mpc-bar span'),
      stats = root.querySelector('.mpc-stats');

  var current = null, frameTimer = null, loading = false;

  function fmtMin(m) {
    if (m == null) return '—';
    var h = Math.floor(m / 60), r = m % 60;
    return h ? h + 'h ' + r + 'm' : r + 'm';
  }
  function cleanJob(j) { return j ? j.replace(/\.(gcode\.)?3mf$/i, '').replace(/[_-]+/g, ' ') : 'Mushbox parts'; }

  function setMode(mode, s) {
    box.setAttribute('data-s', mode);
    root.hidden = hideIdle && (mode === 'idle' || mode === 'offline');
    if (mode === 'live' || mode === 'paused') {
      badge.textContent = mode === 'paused' ? 'Paused' : (s.state === 'PREPARE' ? 'Warming up' : 'Live');
      job.textContent = cleanJob(s.job);
      var pct = s.percent || 0;
      bar.style.width = pct + '%';
      var parts = ['<span><strong>' + pct + '%</strong> done</span>',
                   '<span><strong>' + fmtMin(s.remainingMin) + '</strong> left</span>'];
      if (s.totalLayers) parts.push('<span>Layer <strong>' + (s.layer || 0) + '/' + s.totalLayers + '</strong></span>');
      if (s.nozzleC != null) parts.push('<span>Nozzle <strong>' + s.nozzleC + '°C</strong></span>');
      if (s.bedC != null) parts.push('<span>Bed <strong>' + s.bedC + '°C</strong></span>');
      stats.innerHTML = parts.join('');
      if (!img.classList.contains('on')) {
        msg.innerHTML = '<span class="mpc-shroom">🍄</span><b>Connecting to the camera…</b>';
      }
      startFrames();
    } else {
      stopFrames();
      img.classList.remove('on');
      if (mode === 'offline') {
        badge.textContent = 'Offline';
        msg.innerHTML = '<span class="mpc-shroom">🍄</span><b>Print cam is offline</b>Check back soon.';
      } else {
        badge.textContent = 'Idle';
        msg.innerHTML = '<span class="mpc-shroom">🍄</span><b>The printer is resting</b>' +
          'When Mushbox parts are printing, you can watch them come off the bed live right here.';
      }
    }
  }

  function loadFrame() {
    if (loading || document.hidden) return;
    loading = true;
    var next = new Image();
    next.onload = function () { img.src = next.src; img.classList.add('on'); msg.innerHTML = ''; loading = false; };
    next.onerror = function () { loading = false; };
    next.src = API + '/frame.jpg?t=' + Date.now();
  }
  function startFrames() { if (!frameTimer) { loadFrame(); frameTimer = setInterval(loadFrame, FRAME_MS); } }
  function stopFrames() { clearInterval(frameTimer); frameTimer = null; }

  function poll() {
    fetch(API + '/status.json', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (s) {
        current = s;
        if (!s.online) setMode('offline', s);
        else if (s.printing) setMode(s.state === 'PAUSE' ? 'paused' : 'live', s);
        else setMode('idle', s);
      })
      .catch(function () { setMode('offline', current || {}); });
  }

  document.addEventListener('visibilitychange', function () { if (!document.hidden) { poll(); } });
  setMode('idle', {});
  root.hidden = hideIdle;
  poll();
  setInterval(poll, STATUS_MS);
})();
