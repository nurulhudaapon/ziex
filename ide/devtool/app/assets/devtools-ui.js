(function () {
  var dark = (+(localStorage.getItem('zx-devtool-theme-dark') || 1)) >= 1;
  document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
  document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
})();

(function () {
  var STORAGE_KEY = 'zx-devtool-tree-pane-pct';
  var DEFAULT_PCT = 70;
  var MIN_PCT = 15;
  var MAX_PCT = 85;
  var dragging = false;
  var container = null;
  var currentPct = DEFAULT_PCT;

  function clamp(pct) {
    return Math.max(MIN_PCT, Math.min(MAX_PCT, pct));
  }

  function loadPct() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (raw == null) return DEFAULT_PCT;
      var n = parseFloat(raw);
      return isFinite(n) ? clamp(n) : DEFAULT_PCT;
    } catch (_) {
      return DEFAULT_PCT;
    }
  }

  function applyPct(pct) {
    currentPct = pct;
    document.documentElement.style.setProperty('--zx-tree-pane-pct', String(pct));
  }

  function savePct(pct) {
    try {
      localStorage.setItem(STORAGE_KEY, String(Math.round(pct * 10) / 10));
    } catch (_) {}
  }

  applyPct(loadPct());

  function startDrag(e) {
    var handle = e.target && e.target.closest && e.target.closest('.devtools-resize-handle');
    if (!handle) return;
    container = handle.closest('.devtools-container');
    if (!container) return;
    if (e.type === 'touchstart' && e.touches.length !== 1) return;
    e.preventDefault();
    dragging = true;
    var isColumn = getComputedStyle(container).flexDirection === 'column';
    container.classList.add(isColumn ? 'devtools-dragging-v' : 'devtools-dragging');
    handle.classList.add('active');
  }

  function handleDrag(clientX, clientY) {
    if (!dragging || !container) return;
    var rect = container.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;
    var isColumn = getComputedStyle(container).flexDirection === 'column';
    var pct = isColumn
      ? ((clientY - rect.top) / rect.height) * 100
      : ((clientX - rect.left) / rect.width) * 100;
    applyPct(clamp(pct));
  }

  function stopDrag() {
    if (!dragging) return;
    var handle = container && container.querySelector('.devtools-resize-handle');
    savePct(currentPct);
    dragging = false;
    if (container) {
      container.classList.remove('devtools-dragging');
      container.classList.remove('devtools-dragging-v');
    }
    if (handle) handle.classList.remove('active');
    container = null;
  }

  document.addEventListener('mousedown', startDrag);
  document.addEventListener('touchstart', startDrag, { passive: false });
  document.addEventListener('mousemove', function (e) {
    handleDrag(e.clientX, e.clientY);
  });
  document.addEventListener('touchmove', function (e) {
    if (!dragging || e.touches.length !== 1) return;
    e.preventDefault();
    handleDrag(e.touches[0].clientX, e.touches[0].clientY);
  }, { passive: false });
  document.addEventListener('mouseup', stopDrag);
  document.addEventListener('touchend', stopDrag);
})();
