(function () {
    // ─ Vertical splitter (editor ↔ preview) ─
    const ide = document.getElementById('pg-ide-body');
    const editor = document.getElementById('pg-editor');
    const preview = document.getElementById('pg-preview');
    const vsplit = document.getElementById('pg-splitter');

    let draggingV = false;
    function startVerticalDrag(e) {
        e.preventDefault();
        draggingV = true;
        const isColumn = getComputedStyle(ide).flexDirection === 'column';
        const ideContainer = document.getElementById('playground-ide');
        if (isColumn) {
            ideContainer.classList.add('pg-ide--dragging-v');
        } else {
            ideContainer.classList.add('pg-ide--dragging');
        }
    }
    vsplit.addEventListener('mousedown', startVerticalDrag);
    vsplit.addEventListener('touchstart', startVerticalDrag, { passive: false });

    function handleVerticalDrag(clientX, clientY) {
        const rect = ide.getBoundingClientRect();
        const isColumn = getComputedStyle(ide).flexDirection === 'column';
        if (isColumn) {
            const pct = ((clientY - rect.top) / rect.height) * 100;
            const clamped = Math.max(15, Math.min(85, pct));
            editor.style.flex = '0 0 ' + clamped + '%';
            preview.style.flex = '0 0 ' + (100 - clamped) + '%';
            editor.style.width = '100%';
            preview.style.width = '100%';
        } else {
            const pct = ((clientX - rect.left) / rect.width) * 100;
            const clamped = Math.max(15, Math.min(85, pct));
            editor.style.flex = '0 0 ' + clamped + '%';
            preview.style.flex = '0 0 ' + (100 - clamped) + '%';
            editor.style.height = '100%';
            preview.style.height = '100%';
        }
    }
    document.addEventListener('mousemove', function (e) {
        if (!draggingV) return;
        handleVerticalDrag(e.clientX, e.clientY);
    });
    document.addEventListener('touchmove', function (e) {
        if (!draggingV) return;
        if (e.touches.length !== 1) return;
        const touch = e.touches[0];
        handleVerticalDrag(touch.clientX, touch.clientY);
    }, { passive: false });

    function endVerticalDrag() {
        if (draggingV) {
            draggingV = false;
            const ideContainer = document.getElementById('playground-ide');
            ideContainer.classList.remove('pg-ide--dragging');
            ideContainer.classList.remove('pg-ide--dragging-v');
        }
    }
    document.addEventListener('mouseup', endVerticalDrag);
    document.addEventListener('touchend', endVerticalDrag);

    // ─ Horizontal splitter (browser ↔ terminal) ─
    const browser = document.getElementById('pg-browser');
    const terminal = document.getElementById('pg-terminal');
    const hsplit = document.getElementById('pg-hsplitter');
    const previewEl = document.getElementById('pg-preview');

    let draggingH = false;
    function startHorizontalDrag(e) {
        e.preventDefault();
        draggingH = true;
        document.getElementById('playground-ide').classList.add('pg-ide--dragging-v');
    }
    hsplit.addEventListener('mousedown', startHorizontalDrag);
    hsplit.addEventListener('touchstart', startHorizontalDrag, { passive: false });

    function handleHorizontalDrag(clientY) {
        const rect = previewEl.getBoundingClientRect();
        const pct = ((clientY - rect.top) / rect.height) * 100;
        const clamped = Math.max(15, Math.min(85, pct));
        browser.style.flex = '0 0 ' + clamped + '%';
        terminal.style.height = (100 - clamped) + '%';
        terminal.style.flex = '0 0 ' + (100 - clamped) + '%';
    }
    document.addEventListener('mousemove', function (e) {
        if (!draggingH) return;
        handleHorizontalDrag(e.clientY);
    });
    document.addEventListener('touchmove', function (e) {
        if (!draggingH) return;
        if (e.touches.length !== 1) return;
        const touch = e.touches[0];
        handleHorizontalDrag(touch.clientY);
    }, { passive: false });

    function endHorizontalDrag() {
        if (draggingH) {
            draggingH = false;
            document.getElementById('playground-ide').classList.remove('pg-ide--dragging-v');
        }
    }
    document.addEventListener('mouseup', endHorizontalDrag);
    document.addEventListener('touchend', endHorizontalDrag);


})();