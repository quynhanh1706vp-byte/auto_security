#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p64_${TS}"
echo "[OK] backup ${APP}.bak_p64_${TS}"

JS="static/js/vsp_runtime_error_overlay_v1.js"
mkdir -p static/js

cat > "$JS" <<'JS'
/* P64_RUNTIME_OVERLAY_V1 */
(() => {
  const $ = (sel) => document.querySelector(sel);

  function makePanel() {
    const el = document.createElement("div");
    el.id = "vsp-runtime-overlay";
    el.style.cssText = [
      "position:fixed",
      "right:12px",
      "bottom:12px",
      "z-index:2147483647",
      "width:420px",
      "max-height:48vh",
      "overflow:auto",
      "font:12px/1.35 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace",
      "background:rgba(0,0,0,.80)",
      "border:1px solid rgba(255,255,255,.12)",
      "border-radius:12px",
      "padding:10px",
      "color:#e5e7eb",
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

  function now() {
    const d = new Date();
    return d.toISOString().slice(11, 19);
  }
  function log(line) {
    logEl.textContent += `[${now()}] ${line}\n`;
    logEl.scrollTop = logEl.scrollHeight;
  }

  // Basic meta / mounts
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

  // capture errors
  window.addEventListener("error", (e) => {
    log(`ERROR: ${e.message} @ ${e.filename}:${e.lineno}:${e.colno}`);
  });
  window.addEventListener("unhandledrejection", (e) => {
    const msg = (e && e.reason && (e.reason.stack || e.reason.message)) ? (e.reason.stack || e.reason.message) : String(e.reason);
    log(`UNHANDLED: ${msg}`);
  });

  // patch fetch for visibility
  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if (_fetch) {
    window.fetch = async (...args) => {
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
  }

  // proactive probes (same-origin)
  async function probe() {
    try {
      const res = await fetch("/api/vsp/top_findings_v2?limit=1", { cache: "no-store" });
      const j = await res.json().catch(() => null);
      log(`probe top_findings_v2 status=${res.status} rid=${j && (j.rid || j.run_id) ? (j.rid || j.run_id) : "(no rid)"}`);
    } catch (e) {
      log(`probe top_findings_v2 FAIL ${(e && e.message) ? e.message : String(e)}`);
    }
  }
  setTimeout(probe, 500);

  log("overlay loaded");
})();
JS

echo "[OK] wrote $JS"

python3 - <<'PY'
from pathlib import Path
import re, datetime

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")
MARK = "P64_RUNTIME_OVERLAY_INJECT_V1"
if MARK in s:
    print("[OK] already injected", MARK)
    raise SystemExit(0)

# inject after vsp_tabs4_autorid_v1.js include in /vsp5 HTML
needle = r'<script\s+src="/static/js/vsp_tabs4_autorid_v1\.js[^"]*"></script>'
m = re.search(needle, s)
if not m:
    # fallback: inject before </body> in vsp5 template region
    s2 = re.sub(r'(</body>)', r'  <script src="/static/js/vsp_runtime_error_overlay_v1.js?v=__VSP_TS__"></script>\n\1', s, count=1)
    if s2 == s:
        print("[ERR] cannot find injection point")
        raise SystemExit(2)
    s = s2
else:
    ins = m.group(0) + '\n  <script src="/static/js/vsp_runtime_error_overlay_v1.js?v=__VSP_TS__"></script>\n  <!-- %s -->' % MARK
    s = s[:m.start()] + ins + s[m.end():]

ts = int(datetime.datetime.now().timestamp())
s = s.replace("__VSP_TS__", str(ts))
app.write_text(s, encoding="utf-8")
print("[OK] injected overlay tag", MARK)
PY

echo "== [1] py_compile =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [2] restart =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

echo "== [3] wait /vsp5 up =="
ok=0
for i in $(seq 1 40); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/vsp5" || true)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.2
done
if [ "$ok" = "1" ]; then
  echo "[OK] /vsp5 200"
else
  echo "[WARN] /vsp5 not ready yet (check service logs)"
fi

echo "[DONE] P64 overlay ready. Open: $BASE/vsp5?rid=<RID> and watch overlay."
