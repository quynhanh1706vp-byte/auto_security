#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID_DEFAULT="VSP_CI_20251218_114312"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl; need tar || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_p0_commerce_lock_v1b_${TS}"
echo "[BACKUP] ${APP}.bak_p0_commerce_lock_v1b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_COMMERCE_LOCK_V1B"
if MARK in s:
    print("[OK] already patched:", MARK)
    sys.exit(0)

# ---- ensure request import exists (safe) ----
if re.search(r'(?m)^\s*from\s+flask\s+import\s+.*\brequest\b', s) is None and re.search(r'(?m)^\s*import\s+flask\b', s) is None:
    # try to add request into first "from flask import ..." line
    m = re.search(r'(?m)^\s*from\s+flask\s+import\s+(.+)\s*$', s)
    if m:
        line = m.group(0)
        imports = m.group(1)
        if "request" not in imports:
            new_line = re.sub(r'(?m)^\s*from\s+flask\s+import\s+(.+)\s*$',
                              lambda mm: f"from flask import {mm.group(1)}, request  # {MARK}",
                              line)
            s = s[:m.start()] + new_line + s[m.end():]
    else:
        # fallback: prepend
        s = f"from flask import request  # {MARK}\n" + s

# ---- helper block (insert before app = / create_app / first route def) ----
helper = f"""
# ===================== {MARK} =====================
# Commercial: badge DATA SOURCE + pin dataset (global vs rid) for demo/audit.
import os
from functools import lru_cache
from pathlib import Path as _Path

def _vsp_pin_mode():
    try:
        v = (request.args.get("pin_dataset") or "").strip().lower()
    except Exception:
        v = ""
    if v in ("global","pin_global","g","1","true","yes","on"):
        return "global"
    if v in ("rid","use_rid","r","0","false","off"):
        return "rid"
    return "auto"

@lru_cache(maxsize=1)
def _vsp_find_global_best_path():
    root = os.environ.get("VSP_OUT_ROOT") or "/home/test/Data/SECURITY_BUNDLE/out"
    rootp = _Path(root)
    best = ""
    best_sz = -1
    try:
        for fp in rootp.glob("RUN_*/unified/findings_unified.json"):
            try:
                sz = fp.stat().st_size
            except Exception:
                continue
            if sz > best_sz:
                best, best_sz = str(fp), sz
    except Exception:
        pass
    return best

def _vsp_rid_to_findings_path(rid: str) -> str:
    rid = (rid or "").strip()
    if not rid:
        return ""
    roots = [
        os.environ.get("VSP_OUT_CI_ROOT") or "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    ]
    rels = [
        "unified/findings_unified.json",
        "reports/findings_unified.json",
        "report/findings_unified.json",
        "findings_unified.json",
    ]
    for r in roots:
        base = _Path(r) / rid
        for rel in rels:
            fp = base / rel
            if fp.exists():
                return str(fp)
    return ""

def _vsp_data_source_from_path(from_path: str) -> str:
    p = (from_path or "")
    if ("/SECURITY_BUNDLE/out/" in p) and ("/unified/" in p) and ("out_ci" not in p):
        return "GLOBAL_BEST"
    return "RID"
# =================== /{MARK} ======================
"""

# place helper before first app=/create_app/route def (best effort)
anchors = []
for pat in [r'(?m)^\s*app\s*=\s*', r'(?m)^\s*def\s+create_app\s*\(', r'(?m)^\s*@app\.route\(']:
    m = re.search(pat, s)
    if m: anchors.append(m.start())
pos = min(anchors) if anchors else 0
s = s[:pos] + helper + "\n" + s[pos:]

# ---- inject response fields (string-level, safe-ish) ----
# findings_page_v3: after "from_path": ...
if '"pin_mode": _vsp_pin_mode()' not in s:
    s = re.sub(
        r'(?m)^(?P<ind>\s*)("from_path"\s*:\s*[^,\n]+,\s*)$',
        r'\g<ind>\2\g<ind>"data_source": _vsp_data_source_from_path(from_path),\n\g<ind>"pin_mode": _vsp_pin_mode(),\n',
        s,
        count=1
    )

# top_findings_v1: after "rid_used": ...
if '"rid_used"' in s and '"pin_mode": _vsp_pin_mode()' in s and '"data_source": None' not in s:
    s = re.sub(
        r'(?m)^(?P<ind>\s*)("rid_used"\s*:\s*[^,\n]+,\s*)$',
        r'\g<ind>\2\g<ind>"pin_mode": _vsp_pin_mode(),\n\g<ind>"data_source": None,\n',
        s,
        count=1
    )

# ---- enforce pin behavior by overriding from_path AFTER first from_path assignment inside findings_page_v3 (best effort) ----
def patch_override_in_function(src: str, fname: str) -> str:
    m = re.search(rf'(?ms)^def\s+{re.escape(fname)}\s*\(.*?\):\s*', src)
    if not m:
        print(f"[WARN] cannot find def {fname}()")
        return src
    start = m.start()
    rest = src[m.end():]
    m2 = re.search(r'(?m)^def\s+\w+\s*\(', rest)
    end = m.end() + (m2.start() if m2 else len(rest))
    chunk = src[start:end]

    if "VSP_COMMERCE_PIN_OVERRIDE" in chunk:
        return src

    mi = re.search(r'(?m)^(?P<ind>\s*)from_path\s*=\s*.*$', chunk)
    if not mi:
        print(f"[WARN] {fname}: cannot locate from_path assignment")
        return src

    ind = mi.group("ind")
    block = (
        f"{ind}# VSP_COMMERCE_PIN_OVERRIDE ({MARK})\n"
        f"{ind}try:\n"
        f"{ind}    _pin = _vsp_pin_mode()\n"
        f"{ind}    if _pin == 'global':\n"
        f"{ind}        _gb = _vsp_find_global_best_path()\n"
        f"{ind}        if _gb:\n"
        f"{ind}            from_path = _gb\n"
        f"{ind}    elif _pin == 'rid':\n"
        f"{ind}        _rp = _vsp_rid_to_findings_path(rid) if 'rid' in locals() else ''\n"
        f"{ind}        if _rp:\n"
        f"{ind}            from_path = _rp\n"
        f"{ind}except Exception:\n"
        f"{ind}    pass\n"
    )

    insert_at = mi.end()
    chunk = chunk[:insert_at] + "\n" + block + chunk[insert_at:]
    return src[:start] + chunk + src[end:]

s = patch_override_in_function(s, "findings_page_v3")

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile: vsp_demo_app.py"

# ---- JS: badge + pin buttons + auto append pin_dataset to /api/vsp/* ----
mkdir -p static/js
JS="static/js/vsp_pin_dataset_badge_v1.js"
cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JS'
(function(){
  if (window.__VSP_PIN_BADGE_V1) return;
  window.__VSP_PIN_BADGE_V1 = true;

  const KEY="VSP_PIN_DATASET";
  const getPin=()=> (localStorage.getItem(KEY)||"auto").toLowerCase();
  const setPin=(v)=> localStorage.setItem(KEY,v);

  function ensureBar(){
    let wrap=document.getElementById("vsp-commerce-pin-wrap");
    if (wrap) return wrap;

    wrap=document.createElement("div");
    wrap.id="vsp-commerce-pin-wrap";
    wrap.style.cssText="position:sticky;top:0;z-index:9999;display:flex;gap:8px;align-items:center;justify-content:flex-end;padding:8px 12px;background:rgba(0,0,0,.18);backdrop-filter:blur(6px);border-bottom:1px solid rgba(255,255,255,.08);font-family:ui-sans-serif,system-ui;";

    const badge=document.createElement("span");
    badge.id="vsp-data-source-badge";
    badge.textContent="DATA SOURCE: …";
    badge.title="Waiting for API…";
    badge.style.cssText="padding:4px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.18);color:#eaeaea;font-size:12px;";

    const mode=document.createElement("span");
    mode.id="vsp-pin-mode";
    mode.textContent="PIN: "+getPin().toUpperCase();
    mode.style.cssText="padding:4px 10px;border-radius:999px;border:1px dashed rgba(255,255,255,.18);color:#cfcfcf;font-size:12px;";

    const mkBtn=(txt,val)=>{
      const b=document.createElement("button");
      b.type="button";
      b.textContent=txt;
      b.style.cssText="cursor:pointer;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.06);color:#f2f2f2;font-size:12px;";
      b.onclick=()=>{ setPin(val); mode.textContent="PIN: "+getPin().toUpperCase(); location.reload(); };
      return b;
    };

    wrap.appendChild(badge);
    wrap.appendChild(mode);
    wrap.appendChild(mkBtn("Pin Global","global"));
    wrap.appendChild(mkBtn("Use RID","rid"));
    wrap.appendChild(mkBtn("Auto","auto"));

    document.body.insertBefore(wrap, document.body.firstChild);
    return wrap;
  }

  function addPinParam(url){
    try{
      const pin=getPin();
      if (pin!=="global" && pin!=="rid") return url;
      const u=new URL(url, location.origin);
      if (!u.pathname.startsWith("/api/vsp/")) return url;
      if (!u.searchParams.get("pin_dataset")) u.searchParams.set("pin_dataset", pin);
      return u.toString();
    }catch(e){ return url; }
  }

  function updateBadge(j){
    const badge=document.getElementById("vsp-data-source-badge");
    if (!badge || !j) return;
    const ds=(j.data_source||"").toString().toUpperCase();
    if (ds) badge.textContent="DATA SOURCE: "+ds;
    if (j.from_path) badge.title=String(j.from_path);
    const mode=document.getElementById("vsp-pin-mode");
    if (mode && j.pin_mode) mode.textContent="PIN: "+String(j.pin_mode).toUpperCase();
  }

  const _fetch=window.fetch;
  window.fetch=function(input, init){
    try{
      const url=(typeof input==="string")? addPinParam(input) : addPinParam(input.url);
      if (typeof input==="string") input=url; else input=new Request(url, input);
    }catch(e){}
    return _fetch(input, init).then(async (resp)=>{
      try{
        const ct=resp.headers.get("content-type")||"";
        if (ct.includes("application/json")){
          const j=await resp.clone().json();
          if (j && (j.data_source || j.from_path || j.pin_mode)) updateBadge(j);
        }
      }catch(e){}
      return resp;
    });
  };

  const _open=XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open=function(method, url){
    try{ url=addPinParam(url); }catch(e){}
    return _open.apply(this, [method, url, ...Array.prototype.slice.call(arguments, 2)]);
  };

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", ()=>{ensureBar();});
  else ensureBar();
})();
JS

echo "[OK] wrote $JS"

# ---- inject loader into common bundles (best effort, ignore missing) ----
inject_js(){
  local f="$1"
  [ -f "$f" ] || { echo "[SKIP] missing $f"; return 0; }
  if grep -q "vsp_pin_dataset_badge_v1.js" "$f"; then
    echo "[OK] already injected $f"
    return 0
  fi
  cp -f "$f" "${f}.bak_pininject_${TS}"
  printf '%s\n' \
'(function(){try{if(window.__VSP_PIN_BADGE_V1)return;var s=document.createElement("script");s.src="/static/js/vsp_pin_dataset_badge_v1.js?v="+Date.now();document.head.appendChild(s);}catch(e){}})();' \
"$(cat "$f")" > "$f"
  echo "[OK] injected -> $f"
}
inject_js "static/js/vsp_bundle_tabs5_v1.js"
inject_js "static/js/vsp_tabs4_autorid_v1.js"
inject_js "static/js/vsp_dashboard_luxe_v1.js"
inject_js "static/js/vsp_runs_quick_actions_v1.js"

# ---- restart service if present ----
if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

# ---- probes ----
RID="${RID:-$RID_DEFAULT}"
echo "[PROBE] findings_page_v3 rid=$RID ..."
curl -sS "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok")); print("data_source=",j.get("data_source")); print("pin_mode=",j.get("pin_mode")); print("from_path=",j.get("from_path")); print("total_findings=",j.get("total_findings"))'

echo "[PROBE] top_findings_v1 rid=$RID ..."
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok")); print("rid_used=",j.get("rid_used")); print("pin_mode=",j.get("pin_mode")); print("top_total=",j.get("total"))'

echo "[DONE] Open: $BASE/vsp5?rid=$RID  (Ctrl+F5). Use Pin Global / Use RID / Auto on top."
