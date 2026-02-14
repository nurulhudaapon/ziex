// Minimal JS for draggable split pane
// Usage: <div class="split-pane"><div class="pane-left"></div><div class="split-bar"></div><div class="pane-right"></div></div>

(function() {
  const bar = document.querySelector('.split-bar');
  const left = document.querySelector('.pane-left');
  const right = document.querySelector('.pane-right');
  if (!bar || !left || !right) return;

  let dragging = false;

  bar.addEventListener('mousedown', function(e) {
    dragging = true;
    document.body.style.cursor = 'col-resize';
  });

  document.addEventListener('mousemove', function(e) {
    if (!dragging) return;
    const rect = left.parentNode.getBoundingClientRect();
    let newWidth = e.clientX - rect.left;
    newWidth = Math.max(60, Math.min(newWidth, rect.width - 60));
    left.style.width = newWidth + 'px';
    right.style.width = (rect.width - newWidth - bar.offsetWidth) + 'px';
  });

  document.addEventListener('mouseup', function() {
    dragging = false;
    document.body.style.cursor = '';
  });
})();
