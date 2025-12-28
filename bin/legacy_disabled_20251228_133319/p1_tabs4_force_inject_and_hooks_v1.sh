#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"

JS_AUTORID="static/js/vsp_tabs4_autorid_v1.js"
JS_TABS3="static/js/vsp_tabs3_common_v3.js"
JS_RUNS="static/js/vsp_runs_reports_overlay_v1.js"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$JS_AUTORID" ] || { echo "[ERR] missing $JS_AUTORID"; exit 2; }
[ -f "$JS_TABS3" ] || { echo "[ERR] missing $JS_TABS3"; exit 2; }
[ -f "$JS_RUNS" ]  || { echo "[ERR] missing $JS_RUNS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_tabs4force_${TS}"
cp -f "$JS_AUTORID" "${JS_AUTORID}.bak_tabs4force_${TS}"
cp -f "$JS_TABS3" "${JS_TABS3}.bak_tabs4force_${TS}"
cp -f "$JS_RUNS"  "${JS_RUNS}.bak_tabs4force_${TS}"
echo "[BACKUP] ${APP}.bak_tabs4force_${TS}"
echo "[BACKUP] ${JS_AUTORID}.bak_tabs4force_${TS}"
echo "[BACKUP] ${JS_TABS3}.bak_tabs4force_${TS}"
echo "[BACKUP] ${JS_RUNS}.bak_tabs4force_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile, textwrap

# ----------------------------
# 1) Patch vsp_demo_app.py: after_request inject autorid into 4 tabs (and /reports if HTML)
# ----------------------------
app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1C"

# remove old broken V1B injector block if exists (it injected Jinja into HTML which won't render)
s = re.sub(
    r'(?s)# ===================== VSP_P1_REPORTS_AFTER_REQUEST_INJECT_AUTORID_V1B =====================.*?# ===================== /VSP_P1_REPORTS_AFTER_REQUEST_INJECT_AUTORID_V1B =====================\s*',
    '',
    s
)

if MARK not in s:
    block = textwrap.dedent(r"""
    # ===================== VSP_P1_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1C =====================
    @app.after_request
    def _vsp_after_request_tabs4_inject_autorid(resp):
        # Inject autorid JS into non-dashboard tab pages robustly (do not rely on templates).
        try:
            p = (request.path or "").rstrip("/") or "/"
        except Exception:
            return resp

        # DO NOT touch dashboard:
        if p.startswith("/vsp5"):
            return resp

        # only these "4 tabs" + optional /reports if it is actually HTML
        targets = {"/runs", "/runs_reports", "/settings", "/data_source", "/rule_overrides", "/reports"}

        if p not in targets:
            return resp

        # only HTML responses
        try:
            ct = (resp.headers.get("Content-Type") or "").lower()
        except Exception:
            ct = ""
        if "text/html" not in ct:
            return resp

        try:
            body = resp.get_data(as_text=True)
        except Exception:
            return resp

        if "vsp_tabs4_autorid_v1.js" in body:
            return resp

        # IMPORTANT: cannot use Jinja here (response already rendered). Inject real cache-busted URL.
        try:
            v = str(_VSP_ASSET_V)
        except Exception:
            v = str(int(time.time()))
        tag = f'\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={v}"></script>\n'

        if "</body>" in body:
            body = body.replace("</body>", tag + "</body>", 1)
        else:
            body = body + tag

        try:
            resp.set_data(body)
            resp.headers.pop("Content-Length", None)
            resp.headers["Cache-Control"] = "no-store"
        except Exception:
            return resp
        return resp
    # ===================== /VSP_P1_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1C =====================
    """).strip() + "\n"

    s = s.rstrip() + "\n\n" + block
    app.write_text(s, encoding="utf-8")
    py_compile.compile(str(app), doraise=True)
    print("[OK] patched vsp_demo_app.py with", MARK)
else:
    print("[OK] vsp_demo_app.py already has", MARK)

# ----------------------------
# 2) Patch tabs3_common: define safe reload hooks for Settings/DataSource/RuleOverrides
# ----------------------------
tabs3 = Path("static/js/vsp_tabs3_common_v3.js")
t = tabs3.read_text(encoding="utf-8", errors="replace")
MARK2="VSP_P1_TABS3_COMMON_RELOAD_HOOKS_V1"
if MARK2 not in t:
    addon = r"""
/* VSP_P1_TABS3_COMMON_RELOAD_HOOKS_V1 */
(function(){
  function _clickRefreshHeuristic(){
    try{
      const btns = Array.from(document.querySelectorAll("button,a"));
      const keys = ["refresh","reload","tải lại","làm mới","update","sync"];
      for(const b of btns){
        const tx = (b.textContent||"").trim().toLowerCase();
        if(!tx) continue;
        if(keys.some(k=>tx.includes(k))){
          b.click();
          return true;
        }
      }
    }catch(e){}
    return false;
  }

  async function _emitReloadEvent(kind){
    try{
      window.dispatchEvent(new CustomEvent("vsp:reload-request", {detail:{kind, rid: window.VSP_CURRENT_RID||null}}));
    }catch(e){}
  }

  window.VSP_reloadSettings = async function(){
    await _emitReloadEvent("settings");
    if(_clickRefreshHeuristic()) return;
  };

  window.VSP_reloadDataSource = async function(){
    await _emitReloadEvent("data_source");
    if(_clickRefreshHeuristic()) return;
  };

  window.VSP_reloadRuleOverrides = async function(){
    await _emitReloadEvent("rule_overrides");
    if(_clickRefreshHeuristic()) return;
  };

  // umbrella
  window.VSP_reloadAll = async function(){
    try{ await window.VSP_reloadSettings(); }catch(e){}
    try{ await window.VSP_reloadDataSource(); }catch(e){}
    try{ await window.VSP_reloadRuleOverrides(); }catch(e){}
  };
})();
""".strip() + "\n"
    tabs3.write_text(t.rstrip()+"\n\n"+addon, encoding="utf-8")
    print("[OK] patched", tabs3, "with reload hooks")
else:
    print("[OK] already has", MARK2, "in", tabs3)

# ----------------------------
# 3) Patch runs overlay JS: define reload hooks for Runs/Runs&Reports
# ----------------------------
runs = Path("static/js/vsp_runs_reports_overlay_v1.js")
u = runs.read_text(encoding="utf-8", errors="replace")
MARK3="VSP_P1_RUNS_REPORTS_RELOAD_HOOKS_V1"
if MARK3 not in u:
    addon = r"""
/* VSP_P1_RUNS_REPORTS_RELOAD_HOOKS_V1 */
(function(){
  function _clickRefreshHeuristic(){
    try{
      const btns = Array.from(document.querySelectorAll("button,a"));
      const keys = ["refresh","reload","tải lại","làm mới","update","sync","fetch"];
      for(const b of btns){
        const tx = (b.textContent||"").trim().toLowerCase();
        if(!tx) continue;
        if(keys.some(k=>tx.includes(k))){
          b.click();
          return true;
        }
      }
    }catch(e){}
    return false;
  }

  async function _emitReloadEvent(kind){
    try{
      window.dispatchEvent(new CustomEvent("vsp:reload-request", {detail:{kind, rid: window.VSP_CURRENT_RID||null}}));
    }catch(e){}
  }

  window.VSP_reloadRuns = async function(){
    await _emitReloadEvent("runs");
    _clickRefreshHeuristic();
  };

  window.VSP_reloadReports = async function(){
    await _emitReloadEvent("reports");
    _clickRefreshHeuristic();
  };
})();
""".strip() + "\n"
    runs.write_text(u.rstrip()+"\n\n"+addon, encoding="utf-8")
    print("[OK] patched", runs, "with reload hooks")
else:
    print("[OK] already has", MARK3, "in", runs)

# ----------------------------
# 4) Ensure autorid JS: call the right hooks for 4 tabs (no dashboard)
# (Your file already does, but we harden it: also triggers per-path hook)
# ----------------------------
autorid = Path("static/js/vsp_tabs4_autorid_v1.js")
a = autorid.read_text(encoding="utf-8", errors="replace")
MARK4="VSP_P1_AUTORID_CALL_PATH_HOOKS_V1C"
if MARK4 not in a:
    addon = r"""
/* VSP_P1_AUTORID_CALL_PATH_HOOKS_V1C */
(function(){
  try{
    window.addEventListener("vsp:rid-changed", async ()=>{
      try{
        const p = (location.pathname||"").toLowerCase();
        if(p.startsWith("/vsp5")) return; // never dashboard
        if(p.startsWith("/settings") && typeof window.VSP_reloadSettings==="function") return void window.VSP_reloadSettings();
        if(p.startsWith("/data_source") && typeof window.VSP_reloadDataSource==="function") return void window.VSP_reloadDataSource();
        if(p.startsWith("/rule_overrides") && typeof window.VSP_reloadRuleOverrides==="function") return void window.VSP_reloadRuleOverrides();
        if((p.startsWith("/runs") || p.startsWith("/runs_reports")) && typeof window.VSP_reloadRuns==="function") return void window.VSP_reloadRuns();
        if(p.startsWith("/reports") && typeof window.VSP_reloadReports==="function") return void window.VSP_reloadReports();
      }catch(e){}
    });
  }catch(e){}
})();
""".strip() + "\n"
    autorid.write_text(a.rstrip()+"\n\n"+addon, encoding="utf-8")
    print("[OK] hardened autorid JS with path hooks:", autorid)
else:
    print("[OK] autorid already has", MARK4)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== re-smoke: scripts for 4 tabs =="
for p in /runs /runs_reports /reports /settings /data_source /rule_overrides; do
  echo "== $p =="
  curl -sS "$BASE$p" | grep -oE '/static/js/[^"]+\.js\?v=[0-9]+' | head -n 30
done

echo "== check autorid present in HTML for 4 tabs =="
for p in /runs /runs_reports /reports /settings /data_source /rule_overrides; do
  if curl -sS "$BASE$p" | grep -q "vsp_tabs4_autorid_v1.js"; then
    echo "[OK] $p has autorid js"
  else
    echo "[WARN] $p missing autorid js (likely non-HTML or different content-type)"
  fi
done
