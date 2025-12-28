#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need sed; need grep; need node; need curl

echo "== [P64B] restore vsp_demo_app.py from last good backup (bak_p64) =="
bak="$(ls -1t ${APP}.bak_p64_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  echo "[ERR] cannot find ${APP}.bak_p64_* backup. Available backups:"
  ls -1 ${APP}.bak_* 2>/dev/null | tail -n 20 || true
  exit 2
fi
cp -f "$APP" "${APP}.broken_p64b_$(date +%Y%m%d_%H%M%S)" || true
cp -f "$bak" "$APP"
echo "[OK] restored: $APP <= $bak"

echo "== [1] ensure overlay js exists =="
JS="static/js/vsp_runtime_error_overlay_v1.js"
mkdir -p static/js
if [ ! -f "$JS" ]; then
cat > "$JS" <<'JSX'
/* P64_RUNTIME_OVERLAY_V1 */
(() => {
  const $ = (sel) => document.querySelector(sel);
  function makePanel() {
    const el = document.createElement("div");
    el.id = "vsp-runtime-overlay";
    el.style.cssText = [
      "position:fixed","right:12px","bottom:12px","z-index:2147483647",
      "width:420px","max-height:48vh","overflow:auto",
      "font:12px/1.35 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace",
      "background:rgba(0,0,0,.80)","border:1px solid rgba(255,255,255,.12)",
      "border-radius:12px","padding:10px","color:#e5e7eb",
      "box-shadow:0 10px 30px rgba(0,0,0,.35)"
    ].join(";");
    el.innerHTML = `
      <div style="display:flex;gap:8px;align-items:center;justify-content:space-between;margin-bottom:8px">
        <div><b>VSP Runtime Overlay</b> <span style="opacity:.7">(P64)</span></div>
        <div style="display:flex;gap:6px">
          <button id="vsp-ovl-clear" style="cursor:pointer;border:1px solid rgba(255,255,255,.15);background:rgba(255,255,255,.06);color:#e5e7eb;border-radius:8px;padding:4px 8px">Clear</button>
          <button id="vsp-ovl-hide" style="cursor:pointer;border:1px solid rgba(255,255,255,.15);background:rgba(255,255,255,.06);color:#e5e7eb;border-radius:8px;padding:4px 8px">Hide</button>
        </div>
      </div>
      <div id="vsp-ovl-meta" style="white-space:pre-wrap;opacity:.85;margin-bottom:8px"></div>
      <div id="vsp-ovl-log" style="white-space:pre-wrap"></div>
    `;
    document.documentElement.appendChild(el);
    $("#vsp-ovl-clear").onclick = () => { $("#vsp-ovl-log").textContent = ""; };
    $("#vsp-ovl-hide").onclick = () => { el.style.display = "none"; };
    return el;
  }
  const panel = makePanel();
  const logEl = $("#vsp-ovl-log");
  const metaEl = $("#vsp-ovl-meta");
  const now = () => new Date().toISOString().slice(11,19);
  const log = (line) => { logEl.textContent += `[${now()}] ${line}\n`; logEl.scrollTop = logEl.scrollHeight; };

  function mountStats() {
    const a = document.getElementById("vsp5_root");
    const b = document.getElementById("vsp-dashboard-main");
    const rid = new URL(location.href).searchParams.get("rid") || "";
    metaEl.textContent =
      `url=${location.pathname}${location.search}\n` +
      `rid=${rid || "(empty)"}\n` +
      `#vsp5_root children=${a ? a.children.length : "(missing)"}\n` +
      `#vsp-dashboard-main children=${b ? b.children.length : "(missing)"}\n`;
  }
  mountStats();
  setInterval(mountStats, 1000);

  window.addEventListener("error", (e) => log(`ERROR: ${e.message} @ ${e.filename}:${e.lineno}:${e.colno}`));
  window.addEventListener("unhandledrejection", (e) => {
    const msg = (e && e.reason && (e.reason.stack || e.reason.message)) ? (e.reason.stack || e.reason.message) : String(e.reason);
    log(`UNHANDLED: ${msg}`);
  });

  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if (_fetch) window.fetch = async (...args) => {
    const url = String(args[0] || "");
    try {
      const res = await _fetch(...args);
      if (!res.ok) log(`FETCH ${res.status} ${url}`);
      return res;
    } catch (err) {
      log(`FETCH_FAIL ${url} :: ${(err && err.message) ? err.message : String(err)}`);
      throw err;
    }
  };

  setTimeout(async () => {
    try {
      const res = await fetch("/api/vsp/top_findings_v2?limit=1", { cache: "no-store" });
      const j = await res.json().catch(() => null);
      log(`probe top_findings_v2 status=${res.status} rid=${j && (j.rid || j.run_id) ? (j.rid || j.run_id) : "(no rid)"}`);
    } catch (e) {
      log(`probe top_findings_v2 FAIL ${(e && e.message) ? e.message : String(e)}`);
    }
  }, 500);

  log("overlay loaded");
})();
JSX
  echo "[OK] wrote $JS"
else
  echo "[OK] overlay exists: $JS"
fi

echo "== [2] patch bundle to auto-load overlay (no python injection) =="
B="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$B" "${B}.bak_p64b_${TS}"
python3 - <<'PY'
from pathlib import Path
import re, time
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="P64B_OVERLAY_LOADER_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    raise SystemExit(0)

loader = r"""
/* P64B_OVERLAY_LOADER_V1 */
(function(){
  try{
    if (window.__VSP_P64B_OVERLAY_LOADED) return;
    window.__VSP_P64B_OVERLAY_LOADED = true;
    var sc = document.createElement('script');
    sc.src = '/static/js/vsp_runtime_error_overlay_v1.js?v=' + Date.now();
    sc.defer = true;
    (document.head || document.documentElement).appendChild(sc);
  }catch(_){}
})();
"""

# insert near top (after "use strict" if exists)
m = re.search(r'^[ \t]*["\']use strict["\'];\s*$', s, re.M)
if m:
    insert_at = m.end()
    s = s[:insert_at] + "\n" + loader + "\n" + s[insert_at:]
else:
    s = loader + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] patched bundle overlay loader")
PY

echo "== [3] node --check bundle =="
node --check "$B"
echo "[OK] node --check OK"

echo "== [4] py_compile (restored app) =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [5] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

echo "== [6] verify /vsp5 200 =="
ok=0
for i in $(seq 1 40); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/vsp5" || true)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.2
done
if [ "$ok" = "1" ]; then
  echo "[OK] /vsp5 200"
else
  echo "[WARN] /vsp5 not ready; check journalctl -u $SVC"
fi

echo "[DONE] Open browser: $BASE/vsp5?rid=<RID> (overlay should appear bottom-right)"
