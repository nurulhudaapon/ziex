// TODO: Migrate this to Ziex later for Dogfooding
(function () {
  var proto = location.protocol === "https:" ? "wss:" : "ws:";
  var WS_URL = proto + "//" + location.host + "/.well-known/_zx/devsocket";

  var ws = null;
  // Stays true once the first connection succeeds; used to detect reconnects.
  var everConnected = false;
  var reconnectTimer = null;
  var overlayEl = null;
  var currentDiagnostics = null;
  var overlayDismissed = false;

  // Detect if we're on the error shell page (served by DevServer when app isn't running).
  // On the shell page: no dismiss button, and use full reload when app becomes available.
  var isShellPage = document.title === "ZX Dev";

  function connect() {
    clearTimeout(reconnectTimer);
    ws = new WebSocket(WS_URL);

    ws.onopen = function () {
      if (everConnected) {
        // Reconnected after a drop — server may have restarted without sending
        // an explicit reload message, so fetch the latest page content now.
        if (isShellPage) {
          location.reload();
          return;
        }
        partialUpdate();
      }
      everConnected = true;
    };

    ws.onmessage = function (event) {
      var msg;
      try {
        msg = JSON.parse(event.data);
      } catch (_) {
        return;
      }
      console.log("[zx dev]", msg.type, msg);
      if (msg.type === "reload") {
        // If we're on the error shell, do a full reload to pick up the real app
        // (including <head> styles, etc.)
        if (isShellPage) {
          location.reload();
          return;
        }
        hideOverlay(true);
        partialUpdate();
      } else if (msg.type === "error") {
        var diags = msg.diagnostics || (msg.message ? [{ file: "", line: 0, col: 0, kind: "error", message: msg.message }] : null);
        if (diags) {
          if (currentDiagnostics && JSON.stringify(currentDiagnostics) === JSON.stringify(diags)) {
             // Same error again — only show the indicator if the user had dismissed the overlay.
             // Otherwise, the full overlay is already showing; just leave it.
             if (overlayDismissed) showErrorIndicator();
          } else {
             overlayDismissed = false;
             showErrorOverlay(diags);
          }
        }
      } else if (msg.type === "clear") {
        hideOverlay(true);
      } else if (msg.type === "building") {
        if (overlayEl) overlayEl.remove();
        showBuildingOverlay();
      }
    };

    ws.onclose = function () {
      ws = null;
      reconnectTimer = setTimeout(connect, 500);
    };

    ws.onerror = function () {
      if (ws) ws.close();
    };
  }

  function partialUpdate(attempt) {
    attempt = attempt || 0;
    fetch(location.href, { cache: "no-store", headers: { Accept: "text/html" } })
      .then(function (res) {
        if (!res.ok) throw new Error("bad response");
        return res.text();
      })
      .then(function (html) {
        var parser = new DOMParser();
        var newDoc = parser.parseFromString(html, "text/html");

        if (newDoc.title !== document.title) {
          document.title = newDoc.title;
        }

        var newBody = newDoc.body;
        var curBody = document.body;
        if (!newBody || !curBody) {
          location.reload();
          return;
        }

        // Save overlay reference before replacing innerHTML
        var savedOverlay = overlayEl;
        if (savedOverlay && savedOverlay.parentNode) {
          savedOverlay.parentNode.removeChild(savedOverlay);
        }

        if (newBody.innerHTML !== curBody.innerHTML) {
          curBody.innerHTML = newBody.innerHTML;
          rerunScripts(curBody);
        }

        // Re-append the overlay after innerHTML replacement
        if (savedOverlay) {
          document.body.appendChild(savedOverlay);
        }
      })
      .catch(function () {
        // Inner app may still be starting up — retry with backoff before
        // falling back to a hard reload. Max ~2 s of retries (10 attempts).
        if (attempt < 10) {
          setTimeout(function () { partialUpdate(attempt + 1); }, 200);
        } else {
          location.reload();
        }
      });
  }

  function rerunScripts(root) {
    var scripts = Array.from(root.querySelectorAll("script"));
    for (var i = 0; i < scripts.length; i++) {
      var old = scripts[i];
      // Never re-run the dev script itself — doing so would spawn a second
      // WebSocket instance that creates an infinite reconnect/reload loop.
      if (old.src && old.src.indexOf("_zx/devscript") !== -1) continue;

      // Never re-run external scripts (with src) — they define global
      // identifiers (e.g. const ZigJS) that cannot be re-declared.
      // Only inline scripts (no src) are safe to re-run.
      if (old.src) continue;

      var fresh = document.createElement("script");
      for (var j = 0; j < old.attributes.length; j++) {
        fresh.setAttribute(old.attributes[j].name, old.attributes[j].value);
      }
      fresh.textContent = old.textContent;
      old.parentNode.replaceChild(fresh, old);
    }
  }

  // ── Styles ──────────────────────────────────────────────────────────────────

  var OVERLAY_STYLES = [
    "position:fixed;inset:0;z-index:2147483647;",
    "background:rgba(0,0,0,0.92);color:#e8e8e8;",
    "font-family:'Inter',system-ui,-apple-system,sans-serif;font-size:14px;",
    "display:flex;flex-direction:column;overflow:hidden;"
  ].join("");

  var HEADER_STYLES = [
    "display:flex;align-items:center;gap:12px;padding:16px 20px;",
    "background:#1a1a1a;border-bottom:1px solid #333;",
    "flex-shrink:0;"
  ].join("");

  var ERROR_BADGE_STYLES = [
    "display:inline-flex;align-items:center;gap:6px;",
    "background:rgba(239,68,68,0.15);color:#ef4444;",
    "padding:4px 10px;border-radius:6px;font-weight:600;font-size:13px;",
    "border:1px solid rgba(239,68,68,0.25);"
  ].join("");

  var DISMISS_BTN_STYLES = [
    "margin-left:auto;background:transparent;",
    "border:1px solid #444;color:#999;",
    "cursor:pointer;padding:6px 14px;border-radius:6px;",
    "font-size:12px;font-family:inherit;transition:all 0.15s;"
  ].join("");

  // ── Building indicator ──────────────────────────────────────────────────────

  function showBuildingOverlay() {
    if (overlayEl) overlayEl.remove();
    var el = document.createElement("div");
    el.id = "_zx_overlay";
    el.style.cssText = [
      "position:fixed;bottom:20px;right:20px;z-index:2147483647;",
      "background:#1a1a1a;color:#a3a3a3;border:1px solid #333;",
      "padding:10px 16px;border-radius:8px;font-family:system-ui,sans-serif;",
      "font-size:13px;display:flex;align-items:center;gap:8px;",
      "box-shadow:0 4px 12px rgba(0,0,0,0.4);"
    ].join("");

    el.innerHTML = '<svg width="16" height="16" viewBox="0 0 16 16" style="animation:_zx_spin 1s linear infinite"><circle cx="8" cy="8" r="6" fill="none" stroke="#666" stroke-width="2"/><path d="M8 2a6 6 0 0 1 6 6" fill="none" stroke="#3b82f6" stroke-width="2" stroke-linecap="round"/></svg>' +
      '<style>@keyframes _zx_spin{to{transform:rotate(360deg)}}</style>' +
      '<span>Rebuilding...</span>';
    document.body.appendChild(el);
    overlayEl = el;
  }

  // ── Error overlay (Next.js-style) ──────────────────────────────────────────

  function showErrorOverlay(diagnostics) {
    if (overlayEl) overlayEl.remove();
    currentDiagnostics = diagnostics;
    if (!diagnostics || diagnostics.length === 0) return;

    var overlay = document.createElement("div");
    overlay.id = "_zx_overlay";
    overlay.style.cssText = OVERLAY_STYLES;

    // Header
    var hdr = document.createElement("div");
    hdr.style.cssText = HEADER_STYLES;

    var badge = document.createElement("span");
    badge.style.cssText = ERROR_BADGE_STYLES;
    var errorCount = diagnostics.filter(function (d) { return d.kind === "error"; }).length;
    badge.innerHTML = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="7" stroke="currentColor" stroke-width="1.5"/><path d="M8 4v5M8 11v1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>' +
      (errorCount === 1 ? "1 Error" : errorCount + " Errors");

    hdr.appendChild(badge);

    // Only show Dismiss button when there's a real app behind the overlay
    // (not on the error shell page where there's nothing to dismiss to)
    if (!isShellPage) {
      var btn = document.createElement("button");
      btn.style.cssText = DISMISS_BTN_STYLES;
      btn.textContent = "Dismiss";
      btn.onmouseenter = function () { btn.style.borderColor = "#666"; btn.style.color = "#ccc"; };
      btn.onmouseleave = function () { btn.style.borderColor = "#444"; btn.style.color = "#999"; };
      btn.onclick = function() { hideOverlay(); };
      hdr.appendChild(btn);
    }

    // Body
    var body = document.createElement("div");
    body.style.cssText = "padding:0;overflow:auto;flex:1;";

    // Group: show first error prominently, then notes/warnings below
    var primaryError = null;
    var notes = [];
    for (var i = 0; i < diagnostics.length; i++) {
      if (!primaryError && diagnostics[i].kind === "error") {
        primaryError = diagnostics[i];
      } else {
        notes.push(diagnostics[i]);
      }
    }

    if (primaryError) {
      body.appendChild(buildErrorCard(primaryError, true));
    }

    // Additional diagnostics
    for (var j = 0; j < notes.length; j++) {
      body.appendChild(buildErrorCard(notes[j], false));
    }

    overlay.appendChild(hdr);
    overlay.appendChild(body);
    document.body.appendChild(overlay);
    overlayEl = overlay;

    // ESC to dismiss (only when not on shell page)
    if (!isShellPage) {
      overlay._keyHandler = function (e) {
        if (e.key === "Escape") hideOverlay();
      };
      document.addEventListener("keydown", overlay._keyHandler);
    }
  }

  function buildErrorCard(diag, isPrimary) {
    var card = document.createElement("div");
    card.style.cssText = [
      "margin:0;padding:20px 24px;",
      isPrimary ? "" : "border-top:1px solid #262626;"
    ].join("");

    // File location
    if (diag.file && diag.file.length > 0) {
      var loc = document.createElement("div");
      loc.style.cssText = "margin-bottom:12px;display:flex;align-items:center;gap:8px;";

      var fileEl = document.createElement("a");
      fileEl.style.cssText = [
        "font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;",
        "color:#3b82f6;cursor:pointer;text-decoration:none;"
      ].join("");
      fileEl.onmouseenter = function() { fileEl.style.textDecoration = "underline"; };
      fileEl.onmouseleave = function() { fileEl.style.textDecoration = "none"; };
      fileEl.onclick = function(e) {
        e.preventDefault();
        var url = "/.well-known/_zx/open-in-editor?file=" + encodeURIComponent(diag.file) + "&line=" + diag.line + "&col=" + diag.col;
        console.log("Fetching open-in-editor: " + url + " at " + window.location.origin);
        fetch(url);
      };

      fileEl.textContent = diag.file;
      if (diag.line > 0) {
        fileEl.textContent += ":" + diag.line;
        if (diag.col > 0) fileEl.textContent += ":" + diag.col;
      }

      var kindBadge = document.createElement("span");
      var kindColor = diag.kind === "error" ? "#ef4444" : diag.kind === "warning" ? "#f59e0b" : "#6b7280";
      kindBadge.style.cssText = [
        "font-size:11px;font-weight:600;text-transform:uppercase;",
        "padding:2px 6px;border-radius:4px;",
        "background:" + kindColor + "20;color:" + kindColor + ";"
      ].join("");
      kindBadge.textContent = diag.kind;

      loc.appendChild(fileEl);
      loc.appendChild(kindBadge);
      card.appendChild(loc);
    }

    // Error message
    var msgEl = document.createElement("div");
    msgEl.style.cssText = [
      "font-size:" + (isPrimary ? "18px" : "15px") + ";",
      "font-weight:" + (isPrimary ? "600" : "500") + ";",
      "color:" + (diag.kind === "error" ? "#fca5a5" : diag.kind === "warning" ? "#fcd34d" : "#9ca3af") + ";",
      "line-height:1.5;margin-bottom:12px;",
      "font-family:ui-monospace,Menlo,Consolas,monospace;"
    ].join("");
    msgEl.textContent = diag.message;
    card.appendChild(msgEl);

    // Source context
    if (diag.source) {
      var sourceBlock = document.createElement("div");
      sourceBlock.style.cssText = [
        "background:#111;border:1px solid #262626;border-radius:8px;",
        "overflow:hidden;margin-top:8px;"
      ].join("");

      var pre = document.createElement("pre");
      pre.style.cssText = [
        "margin:0;padding:16px;overflow-x:auto;",
        "font-family:ui-monospace,Menlo,Consolas,monospace;",
        "font-size:13px;line-height:1.7;color:#d4d4d4;tab-size:2;"
      ].join("");

      // Highlight the error line
      var lines = diag.source.split("\n");
      var html = "";
      for (var k = 0; k < lines.length; k++) {
        var line = lines[k];
        if (!line && k === lines.length - 1) continue;
        // Check if this is the error line (line number matches)
        var lineNum = parseInt(line.trim().split("|")[0], 10);
        var isErrorLine = lineNum === diag.line;
        if (isErrorLine) {
          html += '<span style="display:block;background:rgba(239,68,68,0.1);margin:0 -16px;padding:0 16px;border-left:3px solid #ef4444;">';
        }
        html += escapeHtml(line);
        if (isErrorLine) html += "</span>";
        else html += "\n";
      }
      pre.innerHTML = html;
      sourceBlock.appendChild(pre);
      card.appendChild(sourceBlock);
    }

    return card;
  }

  function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function showErrorIndicator() {
    if (overlayEl) overlayEl.remove();
    var el = document.createElement("div");
    el.id = "_zx_overlay";
    el.style.cssText = [
      "position:fixed;bottom:20px;right:20px;z-index:2147483647;",
      "background:#1a1a1a;color:#ef4444;border:1px solid rgba(239,68,68,0.3);",
      "padding:10px 16px;border-radius:8px;font-family:system-ui,sans-serif;",
      "font-size:13px;display:flex;align-items:center;gap:8px;cursor:pointer;",
      "box-shadow:0 4px 12px rgba(0,0,0,0.4);transition:transform 0.1s;"
    ].join("");
    el.onmouseenter = function() { el.style.transform = "scale(1.05)"; };
    el.onmouseleave = function() { el.style.transform = "scale(1)"; };
    el.onclick = function() { showErrorOverlay(currentDiagnostics); };

    var errorCount = currentDiagnostics.filter(function (d) { return d.kind === "error"; }).length;
    el.innerHTML = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="7" stroke="currentColor" stroke-width="1.5"/><path d="M8 4v5M8 11v1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>' +
      '<span>' + (errorCount === 1 ? "1 Error" : errorCount + " Errors") + '</span>';
    document.body.appendChild(el);
    overlayEl = el;
  }

  function hideOverlay(completely) {
    if (overlayEl) {
      if (overlayEl._keyHandler) {
        document.removeEventListener("keydown", overlayEl._keyHandler);
      }
      overlayEl.remove();
      overlayEl = null;
    }
    if (completely) {
      currentDiagnostics = null;
      overlayDismissed = false;
    } else if (currentDiagnostics) {
      overlayDismissed = true;
      showErrorIndicator();
    }
  }

  connect();
})();
