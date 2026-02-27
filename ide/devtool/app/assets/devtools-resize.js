(function () {
  const container = document.querySelector('.devtools-container');
  const handle = document.querySelector('.devtools-resize-handle');
  if (!handle || !container) return;

  const sidebar = handle.previousElementSibling;
  let dragging = false;

  function startDrag(e) {
    if (e.type === 'touchstart' && e.touches.length !== 1) return;
    
    e.preventDefault();
    dragging = true;
    const isColumn = getComputedStyle(container).flexDirection === 'column';
    container.classList.add(isColumn ? 'devtools-dragging-v' : 'devtools-dragging');
    handle.classList.add('active');
  }

  function handleDrag(clientX, clientY) {
    if (!dragging) return;

    const rect = container.getBoundingClientRect();
    const isColumn = getComputedStyle(container).flexDirection === 'column';

    if (isColumn) {
      const pct = ((clientY - rect.top) / rect.height) * 100;
      const clamped = Math.max(15, Math.min(85, pct));
      sidebar.style.flex = '0 0 ' + clamped + '%';
      sidebar.style.height = clamped + '%';
      sidebar.style.width = '100%';
    } else {
      const pct = ((clientX - rect.left) / rect.width) * 100;
      const clamped = Math.max(15, Math.min(85, pct));
      sidebar.style.flex = '0 0 ' + clamped + '%';
      sidebar.style.width = clamped + '%';
      sidebar.style.height = '100%';
    }
  }

  handle.addEventListener('mousedown', startDrag);
  handle.addEventListener('touchstart', startDrag, { passive: false });

  document.addEventListener('mousemove', function (e) {
    handleDrag(e.clientX, e.clientY);
  });

  document.addEventListener('touchmove', function (e) {
    if (!dragging || e.touches.length !== 1) return;
    const touch = e.touches[0];
    handleDrag(touch.clientX, touch.clientY);
  }, { passive: false });

  function stopDrag() {
    if (dragging) {
      dragging = false;
      container.classList.remove('devtools-dragging');
      container.classList.remove('devtools-dragging-v');
      handle.classList.remove('active');
    }
  }

  document.addEventListener('mouseup', stopDrag);
  document.addEventListener('touchend', stopDrag);
})();


