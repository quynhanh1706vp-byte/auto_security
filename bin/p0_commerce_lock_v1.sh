#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl; need tar

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_p0_commerce_lock_${TS}"
echo "[BACKUP] ${APP}.bak_p0_commerce_lock_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_COMMERCE_LOCK_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    sys.exit(0)

# 0) ensure request import exists
if re.search(r'^\s*from\s+flask\s+import\s+.*\brequest\b', s, flags=re.M) is None:
    # insert a simple import after first flask import or near top
    m = re.search(r'^\s*from\s+flask\s+import\s+.*$', s, flags=re.M)
    if m:
        ins = m.group(0) + "\nfrom flask import request  # added by VSP_P0_COMMERCE_LOCK_V1\n"
        s = s[:m.start()] + ins + s[m.end():]
    else:
        # fallback: add at top
        s = "from flask import request  # added by VSP_P0_COMMERCE_LOCK_V1\n" + s

# 1) insert helper block near top (after imports)
helper = r'''
# ===================== VSP_P0_COMMERCE_LOCK_V1 =====================
# Data source badge + pin dataset (global vs rid) for commercial demo/audit.
import os
from functools import lru_cache
from pathlib import Path as _Path

def _vsp_pin_mode():
    v = (request.args.get("pin_dataset") or "").strip().lower()
    if v in ("global","pin_global","g","1","true","yes","on"):
        return "global"
    if v in ("rid","use_rid","r","0","false","off"):
        return "rid"
    return "auto"

@lru_cache(maxsize=1)
def _vsp_find_global_best_path():
    # Prefer scanning /home/test/Data/SECURITY_BUNDLE/out for the biggest unified/findings_unified.json
    root = os.environ.get("VSP_OUT_ROOT") or "/home/test/Data/SECURITY_BUNDLE/out"
    rootp = _Path(root)
    best = None
    best_sz = -1
    try:
        for fp in rootp.glob("RUN_*/unified/findings_unified.json"):
            try:
                sz = fp.stat().st_size
            except Exception:
                continue
            if sz > best_sz:
                best, best_sz = fp, sz
    except Exception:
        pass
    return str(best) if best else ""

def _vsp_rid_to_findings_path(rid: str) -> str:
    # Best-effort: check common out_ci layouts
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
    # Consider "GLOBAL_BEST" if it comes from /SECURITY_BUNDLE/out/RUN_*/unified/
    if ("/SECURITY_BUNDLE/out/" in p) and ("/unified/" in p) and ("out_ci" not in p):
        return "GLOBAL_BEST"
    return "RID"
# =================== /VSP_P0_COMMERCE_LOCK_V1 ======================
'''

# Insert helper after the first block of imports (heuristic)
if MARK not in s:
    m = re.search(r'(?ms)\A(.*?\n)(\s*app\s*=|\s*def\s+create_app|\s*@app\.)', s)
    if m:
        head = s[:m.start(2)]
        tail = s[m.start(2):]
        if "VSP_P0_COMMERCE_LOCK_V1" not in head:
            head = head + helper.replace("VSP_P0_COMMERCE_LOCK_V1", MARK)
        s = head + tail
    else:
        s = helper.replace("VSP_P0_COMMERCE_LOCK_V1", MARK) + "\n" + s

# 2) patch JSON responses (findings_page_v3 + top_findings_v1) by injecting fields next to from_path / rid_used
def inject_after_key(route_name: str, key: str, inject: str):
    nonlocal_s = None

inject_findings = r'''
      "data_source": _vsp_data_source_from_path(from_path),
      "pin_mode": _vsp_pin_mode(),
'''.rstrip("\n")

inject_top = r'''
      "data_source": _vsp_data_source_from_path(from_path) if "from_path" in locals() else None,
      "pin_mode": _vsp_pin_mode(),
'''.rstrip("\n")

# A) findings_page_v3: ensure we can force pin behavior by overriding from_path early, if pin_dataset present
# Insert a small block right after function starts (best-effort)
def patch_route_begin(route_pat: str, insert_block: str):
    nonlocal s
    m = re.search(route_pat, s, flags=re.M)
    if not m:
        return False
    # find the def line after decorator
    start = m.end()
    md = re.search(r'(?m)^\s*def\s+[a-zA-Z0-9_]+\s*\(.*\):\s*$', s[start:])
    if not md:
        return False
    def_pos = start + md.end()
    # insert after first line(s) inside function indentation
    # detect indentation from next non-empty line
    after = s[def_pos:]
    mn = re.search(r'(?m)^\s*(?P<ind>\s+)\S', after)
    ind = mn.group("ind") if mn else "    "
    block = "\n" + "\n".join(ind + line for line in insert_block.strip("\n").splitlines()) + "\n"
    # avoid double insert
    if "pin_dataset" in after[:4000]:
        return True
    s = s[:def_pos] + block + s[def_pos:]
    return True

route_findings = r'^\s*@.*\(\s*[\'"]\/api\/vsp\/findings_page_v3[\'"]\s*\)\s*$'
route_top      = r'^\s*@.*\(\s*[\'"]\/api\/vsp\/top_findings_v1[\'"]\s*\)\s*$'

insert_pin_logic = r'''
# --- pin dataset (commercial) ---
_pin = _vsp_pin_mode()
_force_global = (_pin == "global")
_force_rid = (_pin == "rid")
# If user pins GLOBAL, override from_path later to global best.
# If user pins RID, we will try to keep RID path (no global fallback) if available.
'''

patch_route_begin(route_findings, insert_pin_logic)
patch_route_begin(route_top, insert_pin_logic)

# B) inject response fields by spotting "from_path" / "rid_used" in jsonify dict blocks (best-effort string insert)
def inject_in_dict(key: str, inject_block: str):
    nonlocal s
    # only inject once
    if '"pin_mode": _vsp_pin_mode()' in s:
        return
    # inject after "from_path": ...
    pat = rf'(?m)^(?P<ind>\s*)("{re.escape(key)}"\s*:\s*[^,\n]+,\s*)$'
    m = re.search(pat, s)
    if not m:
        return
    ind = m.group("ind")
    ins = "\n".join(ind + line for line in inject_block.splitlines()) + "\n"
    s = s[:m.end()] + ins + s[m.end():]

inject_in_dict("from_path", inject_findings)

# for top_findings_v1, may not include from_path; but we at least want pin_mode + data_source.
# inject after "rid_used" if present
if '"rid_used"' in s and '"pin_mode": _vsp_pin_mode()' not in s:
    pat = r'(?m)^(?P<ind>\s*)("rid_used"\s*:\s*[^,\n]+,\s*)$'
    m = re.search(pat, s)
    if m:
        ind = m.group("ind")
        ins = ind + '"pin_mode": _vsp_pin_mode(),\n' + ind + '"data_source": None,\n'
        s = s[:m.end()] + ins + s[m.end():]

# C) ensure pin actually affects from_path (override near any assignment to from_path)
# Insert a small override after the first "from_path =" inside findings_page_v3 handler (best-effort).
def override_after_first_from_path(route_pat: str):
    nonlocal s
    m = re.search(route_pat, s, flags=re.M)
    if not m:
        return False
    start = m.end()
    # limit to a window to avoid patching unrelated blocks
    window = s[start:start+12000]
    mi = re.search(r'(?m)^(?P<ind>\s*)from_path\s*=\s*.+$', window)
    if not mi:
        return False
    ind = mi.group("ind")
    insert = f'''
{ind}# --- VSP commerce pin override ---
{ind}try:
{ind}    _pin = _vsp_pin_mode()
{ind}    if _pin == "global":
{ind}        _gb = _vsp_find_global_best_path()
{ind}        if _gb:
{ind}            from_path = _gb
{ind}    elif _pin == "rid":
{ind}        _rp = _vsp_rid_to_findings_path(rid) if "rid" in locals() else ""
{ind}        if _rp:
{ind}            from_path = _rp
{ind}except Exception:
{ind}    pass
'''
    # avoid double
    if "VSP commerce pin override" in window:
        return True
    pos = start + mi.end()
    s = s[:pos] + insert + s[pos:]
    return True

override_after_first_from_path(route_findings)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile: vsp_demo_app.py"

# 3) create JS: badge + pin buttons + auto-append pin_dataset to /api/vsp/* calls
mkdir -p static/js
JS="static/js/vsp_pin_dataset_badge_v1.js"
cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JS'
/* vsp_pin_dataset_badge_v1.js
 * - Shows badge: DATA SOURCE: GLOBAL_BEST / RID
 * - Adds 2 buttons: Pin Global / Use RID (stored in localStorage)
 * - Auto-appends ?pin_dataset=global|rid to /api/vsp/* calls via fetch/XHR interception
 */
(function(){
  if (window.__VSP_PIN_BADGE_V1) return;
  window.__VSP_PIN_BADGE_V1 = true;

  const KEY = "VSP_PIN_DATASET";
  function getPin(){ return (localStorage.getItem(KEY) || "auto").toLowerCase(); }
  function setPin(v){ localStorage.setItem(KEY, v); }

  function ensureBar(){
    // Try find a reasonable top container
    const candidates = [
      document.querySelector("#vsp-topbar"),
      document.querySelector(".vsp-topbar"),
      document.querySelector("header"),
      document.querySelector("body")
    ].filter(Boolean);
    const host = candidates[0];
    if (!host) return null;

    let wrap = document.getElementById("vsp-commerce-pin-wrap");
    if (wrap) return wrap;

    wrap = document.createElement("div");
    wrap.id = "vsp-commerce-pin-wrap";
    wrap.style.cssText = "position:sticky;top:0;z-index:9999;display:flex;gap:8px;align-items:center;justify-content:flex-end;padding:8px 12px;background:rgba(0,0,0,.18);backdrop-filter:blur(6px);border-bottom:1px solid rgba(255,255,255,.08);font-family:ui-sans-serif,system-ui;";

    const badge = document.createElement("span");
    badge.id = "vsp-data-source-badge";
    badge.textContent = "DATA SOURCE: …";
    badge.title = "Waiting for API…";
    badge.style.cssText = "padding:4px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.18);color:#eaeaea;font-size:12px;letter-spacing:.2px;";

    const mode = document.createElement("span");
    mode.id = "vsp-pin-mode";
    mode.textContent = "PIN: " + getPin().toUpperCase();
    mode.style.cssText = "padding:4px 10px;border-radius:999px;border:1px dashed rgba(255,255,255,.18);color:#cfcfcf;font-size:12px;";

    function mkBtn(txt, val){
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = txt;
      b.style.cssText = "cursor:pointer;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.06);color:#f2f2f2;font-size:12px;";
      b.onclick = function(){
        setPin(val);
        mode.textContent = "PIN: " + getPin().toUpperCase();
        // Hard reload for clean demo
        location.reload();
      };
      return b;
    }

    const btnGlobal = mkBtn("Pin Global", "global");
    const btnRid    = mkBtn("Use RID", "rid");
    const btnAuto   = mkBtn("Auto", "auto");

    wrap.appendChild(badge);
    wrap.appendChild(mode);
    wrap.appendChild(btnGlobal);
    wrap.appendChild(btnRid);
    wrap.appendChild(btnAuto);

    // Put it at top of body to be visible across tabs
    if (host === document.body) {
      document.body.insertBefore(wrap, document.body.firstChild);
    } else {
      host.insertBefore(wrap, host.firstChild);
    }
    return wrap;
  }

  function updateBadge(j){
    if (!j || typeof j !== "object") return;
    const badge = document.getElementById("vsp-data-source-badge");
    if (!badge) return;

    const ds = (j.data_source || "").toString().toUpperCase();
    if (ds) badge.textContent = "DATA SOURCE: " + ds;

    const fp = (j.from_path || "").toString();
    if (fp) badge.title = fp;

    const pm = (j.pin_mode || "").toString().toUpperCase();
    const mode = document.getElementById("vsp-pin-mode");
    if (mode && pm) mode.textContent = "PIN: " + pm;
  }

  function addPinParam(url){
    try{
      const pin = getPin();
      if (pin !== "global" && pin !== "rid") return url;
      const u = new URL(url, location.origin);
      // Only touch /api/vsp/*
      if (!u.pathname.startsWith("/api/vsp/")) return url;
      if (!u.searchParams.get("pin_dataset")) u.searchParams.set("pin_dataset", pin);
      return u.toString();
    }catch(e){
      return url;
    }
  }

  // fetch interceptor
  const _fetch = window.fetch;
  window.fetch = function(input, init){
    try{
      const url = (typeof input === "string") ? addPinParam(input) : addPinParam(input.url);
      if (typeof input === "string") input = url;
      else input = new Request(url, input);
    }catch(e){}
    return _fetch(input, init).then(async (resp)=>{
      try{
        const ct = resp.headers.get("content-type") || "";
        if (ct.includes("application/json")) {
          const clone = resp.clone();
          const j = await clone.json();
          // Update badge when any API returns these fields
          if (j && (j.data_source || j.from_path || j.pin_mode)) updateBadge(j);
        }
      }catch(e){}
      return resp;
    });
  };

  // XHR interceptor
  const _open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url){
    try{ url = addPinParam(url); }catch(e){}
    return _open.apply(this, [method, url, ...Array.prototype.slice.call(arguments, 2)]);
  };

  // init
  function boot(){
    ensureBar();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
JS

echo "[OK] wrote $JS"

# 4) ensure badge JS is loaded: patch common bundles to inject it (best-effort)
inject_js(){
  local f="$1"
  [ -f "$f" ] || return 0
  if grep -q "vsp_pin_dataset_badge_v1.js" "$f"; then
    echo "[OK] injector already in $f"
    return 0
  fi
  cp -f "$f" "${f}.bak_pininject_${TS}"
  # prepend a tiny loader
  printf '%s\n' \
'(function(){try{if(window.__VSP_PIN_BADGE_V1)return;var s=document.createElement("script");s.src="/static/js/vsp_pin_dataset_badge_v1.js?v="+Date.now();document.head.appendChild(s);}catch(e){}})();' \
"$(cat "$f")" > "$f"
  echo "[OK] injected pin badge loader into $f"
}

inject_js "static/js/vsp_bundle_tabs5_v1.js"
inject_js "static/js/vsp_tabs4_autorid_v1.js"
inject_js "static/js/vsp_dashboard_luxe_v1.js"
inject_js "static/js/vsp_runs_quick_actions_v1.js"

# 5) restart service if systemd exists (optional)
if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

# 6) probes
OUT="/tmp/vsp_p0_commerce_lock_${TS}"
mkdir -p "$OUT"

RID="${RID:-VSP_CI_20251218_114312}"

echo "[PROBE] findings_page_v3 (rid=$RID, limit=1) ..."
curl -sS "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok")); print("data_source=",j.get("data_source")); print("pin_mode=",j.get("pin_mode")); print("from_path=",j.get("from_path")); print("total_findings=",j.get("total_findings"))' \
 | tee "$OUT/probe_findings_page_v3.txt"

echo "[PROBE] top_findings_v1 (rid=$RID, limit=5) ..."
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok")); print("rid_used=",j.get("rid_used")); print("pin_mode=",j.get("pin_mode")); print("top_total=",j.get("total"));' \
 | tee "$OUT/probe_top_findings_v1.txt"

# 7) snapshot key pages
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  f="$OUT/$(echo "$p" | tr '/?' '__').html"
  curl -sS --max-time 6 "$BASE$p?rid=$RID" -o "$f" || true
done

# 8) pack tgz
TGZ="/tmp/VSP_UI_P0_COMMERCE_LOCK_${TS}.tgz"
tar -czf "$TGZ" -C /tmp "vsp_p0_commerce_lock_${TS}"
echo "[OK] packed: $TGZ"
echo "[DONE] Open: $BASE/vsp5?rid=$RID (Ctrl+F5). Use Pin Global / Use RID buttons on top."
