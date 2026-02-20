(function () {
    // ─ Vertical splitter (editor ↔ preview) ─
    const ide = document.getElementById('pg-ide-body');
    const editor = document.getElementById('pg-editor');
    const preview = document.getElementById('pg-preview');
    const vsplit = document.getElementById('pg-splitter');

    let draggingV = false;
    vsplit.addEventListener('mousedown', function (e) {
        e.preventDefault();
        draggingV = true;
        const isColumn = getComputedStyle(ide).flexDirection === 'column';
        const ideContainer = document.getElementById('playground-ide');
        if (isColumn) {
            ideContainer.classList.add('pg-ide--dragging-v');
        } else {
            ideContainer.classList.add('pg-ide--dragging');
        }
    });

    document.addEventListener('mousemove', function (e) {
        if (!draggingV) return;
        const rect = ide.getBoundingClientRect();
        const isColumn = getComputedStyle(ide).flexDirection === 'column';
        
        if (isColumn) {
            const pct = ((e.clientY - rect.top) / rect.height) * 100;
            const clamped = Math.max(15, Math.min(85, pct));
            editor.style.flex = '0 0 ' + clamped + '%';
            preview.style.flex = '0 0 ' + (100 - clamped) + '%';
            editor.style.width = '100%';
            preview.style.width = '100%';
        } else {
            const pct = ((e.clientX - rect.left) / rect.width) * 100;
            const clamped = Math.max(15, Math.min(85, pct));
            editor.style.flex = '0 0 ' + clamped + '%';
            preview.style.flex = '0 0 ' + (100 - clamped) + '%';
            editor.style.height = '100%';
            preview.style.height = '100%';
        }
    });

    document.addEventListener('mouseup', function () {
        if (draggingV) {
            draggingV = false;
            const ideContainer = document.getElementById('playground-ide');
            ideContainer.classList.remove('pg-ide--dragging');
            ideContainer.classList.remove('pg-ide--dragging-v');
        }
    });

    // ─ Horizontal splitter (browser ↔ terminal) ─
    const browser = document.getElementById('pg-browser');
    const terminal = document.getElementById('pg-terminal');
    const hsplit = document.getElementById('pg-hsplitter');
    const previewEl = document.getElementById('pg-preview');

    let draggingH = false;
    hsplit.addEventListener('mousedown', function (e) {
        e.preventDefault();
        draggingH = true;
        document.getElementById('playground-ide').classList.add('pg-ide--dragging-v');
    });

    document.addEventListener('mousemove', function (e) {
        if (!draggingH) return;
        const rect = previewEl.getBoundingClientRect();
        const pct = ((e.clientY - rect.top) / rect.height) * 100;
        const clamped = Math.max(15, Math.min(85, pct));
        browser.style.flex = '0 0 ' + clamped + '%';
        terminal.style.height = (100 - clamped) + '%';
        terminal.style.flex = '0 0 ' + (100 - clamped) + '%';
    });

    document.addEventListener('mouseup', function () {
        if (draggingH) {
            draggingH = false;
            document.getElementById('playground-ide').classList.remove('pg-ide--dragging-v');
        }
    });


})();