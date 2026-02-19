(function() {
  var handle = document.querySelector('.devtools-resize-handle');
  if (!handle) return;
  var sidebar = handle.previousElementSibling;
  var dragging = false;

  handle.addEventListener('mousedown', function(e) {
    e.preventDefault();
    dragging = true;
    handle.classList.add('active');
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  });

  document.addEventListener('mousemove', function(e) {
    if (!dragging) return;
    var container = sidebar.parentNode;
    var rect = container.getBoundingClientRect();
    var w = Math.min(Math.max(200, e.clientX - rect.left), rect.width - 200);
    sidebar.style.width = w + 'px';
  });

  document.addEventListener('mouseup', function() {
    if (!dragging) return;
    dragging = false;
    handle.classList.remove('active');
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
  });
})();
