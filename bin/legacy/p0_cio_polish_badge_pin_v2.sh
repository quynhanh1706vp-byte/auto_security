#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_cio_badgepin_v2_${TS}"
echo "[BACKUP] ${APP}.bak_cio_badgepin_v2_${TS}"

# 1) Backend: after_request inject data_source + pin_mode into findings_page_v3 JSON
python3 - <<'PY'
from pathlib import Path
import re, json

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_CIO_BADGEPIN_V2_AFTER_REQUEST"

if MARK in s:
    print("[OK] already patched:", MARK)
else:
    block = f'''
# ===================== {MARK} =====================
@app.after_request
def vsp_after_request_badgepin_v2(resp):
    try:
        # only touch small JSON responses we care about
        if request.path not in ("/api/vsp/findings_page_v3",):
            return resp
        ct = (resp.content_type or "")
        if "application/json" not in ct:
            return resp
        j = resp.get_json(silent=True)
        if not isinstance(j, dict):
            return resp

        pin_mode = (request.args.get("pin") or request.args.get("pin_mode") or "").strip().lower() or None

        # infer data source from from_path (ground truth)
        fp = (j.get("from_path") or "").strip()
        data_source = None
        if fp:
            if ("/home/test/Data/SECURITY_BUNDLE/out/" in fp) and ("/unified/findings_unified.json" in fp):
                data_source = "GLOBAL_BEST"
            else:
                data_source = "RID"

        if data_source is not None:
            j["data_source"] = data_source
        if pin_mode is not None:
            j["pin_mode"] = pin_mode

        out = jsonify(j)
        # preserve headers that matter
        for hk in ("X-VSP-RELEASE-TS","X-VSP-RELEASE-SHA","X-VSP-RELEASE-PKG","Cache-Control","X-VSP-ASSET-V","X-VSP-ASSET-REWRITE"):
            if hk in resp.headers and hk not in out.headers:
                out.headers[hk] = resp.headers[hk]
        return out
    except Exception:
        return resp
# =================== /{MARK} ======================
'''
    m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
    if m:
        s = s[:m.start()] + block + "\n" + s[m.start():]
    else:
        s = s + "\n" + block
    p.write_text(s, encoding="utf-8")
    print("[OK] inserted after_request injector:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

# 2) Frontend: badge + pin buttons (freeze-safe)
JS_BADGE="static/js/vsp_pin_dataset_badge_v2.js"
cat > "$JS_BADGE" <<'JS'
/* VSP_PIN_DATASET_BADGE_V2 (freeze-safe) */
(function(){
  if (window.__VSP_BADGEPIN_V2_LOADED) return;
  window.__VSP_BADGEPIN_V2_LOADED = true;

  const LS_KEY = "vsp_pin_mode_v2"; // auto|global|rid
  const MODES = ["auto","global","rid"];
  const safeGetMode = () => {
    const m = (localStorage.getItem(LS_KEY) || "auto").toLowerCase();
    return MODES.includes(m) ? m : "auto";
  };
  const setMode = (m) => {
    if (!MODES.includes(m)) m = "auto";
    localStorage.setItem(LS_KEY, m);
  };

  const qs = new URLSearchParams(location.search);
  const rid = qs.get("rid") || "";

  function el(tag, cls, text){
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function ensureHost(){
    let host = document.getElementById("vsp-topbar") || document.querySelector(".vsp-topbar") || document.body;
    const wrap = el("div", "vsp-badgepin-v2");
    wrap.style.cssText = [
      "position:fixed","top:10px","right:12px","z-index:99999",
      "display:flex","gap:8px","align-items:center",
      "background:rgba(12,14,18,.92)","border:1px solid rgba(255,255,255,.10)",
      "padding:8px 10px","border-radius:10px",
      "font:12px/1.2 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
      "color:#e8e8e8",
      "box-shadow:0 10px 30px rgba(0,0,0,.35)"
    ].join(";");
    document.body.appendChild(wrap);
    return wrap;
  }

  function btn(label, mode){
    const b = el("button", "");
    b.textContent = label;
    b.type = "button";
    b.style.cssText = [
      "cursor:pointer","user-select:none",
      "border-radius:8px","padding:6px 8px",
      "border:1px solid rgba(255,255,255,.14)",
      "background:rgba(255,255,255,.06)","color:#fff"
    ].join(";");
    b.addEventListener("click", () => {
      setMode(mode);
      // keep rid, add pin param for transparency (backend may or may not honor)
      const u = new URL(location.href);
      u.searchParams.set("rid", rid);
      u.searchParams.set("pin", mode);
      location.href = u.toString();
    }, {passive:true});
    return b;
  }

  function pill(text){
    const p = el("span","");
    p.textContent = text;
    p.style.cssText = [
      "padding:6px 8px","border-radius:999px",
      "border:1px solid rgba(255,255,255,.12)",
      "background:rgba(0,0,0,.25)"
    ].join(";");
    return p;
  }

  async function fetchDataSource(){
    // call findings_page_v3 (small, limit=1) to know effective from_path -> data_source
    const mode = safeGetMode();
    const u = "/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid) + "&limit=1&offset=0&pin=" + encodeURIComponent(mode);
    try{
      const r = await fetch(u, {cache:"no-store", credentials:"same-origin"});
      const j = await r.json();
      return {
        ok: !!j.ok,
        data_source: j.data_source || "UNKNOWN",
        pin_mode: j.pin_mode || mode,
        from_path: j.from_path || ""
      };
    }catch(e){
      return { ok:false, data_source:"ERR", pin_mode:safeGetMode(), from_path:"" };
    }
  }

  function paint(wrap, info){
    wrap.innerHTML = "";
    const mode = safeGetMode();

    const ds = pill("DATA SOURCE: " + (info.data_source || "UNKNOWN"));
    const pm = pill("PIN: " + mode.toUpperCase());
    const rp = pill("RID: " + (rid ? rid : "(none)"));

    wrap.appendChild(ds);
    wrap.appendChild(pm);
    wrap.appendChild(rp);

    const sep = el("span","", " ");
    sep.style.cssText="opacity:.6";
    wrap.appendChild(sep);

    wrap.appendChild(btn("AUTO", "auto"));
    wrap.appendChild(btn("PIN GLOBAL", "global"));
    wrap.appendChild(btn("USE RID", "rid"));
  }

  function boot(){
    const wrap = ensureHost();
    // paint quickly first
    paint(wrap, {data_source:"…", pin_mode:safeGetMode(), from_path:""});
    // then async update
    setTimeout(async () => {
      const info = await fetchDataSource();
      paint(wrap, info);
    }, 50);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, {once:true});
  } else {
    boot();
  }
})();
JS

echo "[OK] wrote $JS_BADGE"

# 3) Inject loader into main dashboard JS (safe, no duplicates)
inject_loader(){
  local F="$1"
  [ -f "$F" ] || return 0
  if grep -q "VSP_BADGEPIN_V2_LOADER" "$F" 2>/dev/null; then
    echo "[OK] already injected: $F"
    return 0
  fi
  cp -f "$F" "${F}.bak_badgepin_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re
p=Path(r"""'"$F"'""")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_BADGEPIN_V2_LOADER"
loader=r'''
// %s
(function(){
  try{
    if (window.__VSP_BADGEPIN_V2_LOADER) return;
    window.__VSP_BADGEPIN_V2_LOADER = true;
    var id="vsp-pin-dataset-badge-v2";
    if (document.getElementById(id)) return;
    var sc=document.createElement("script");
    sc.id=id;
    sc.src="/static/js/vsp_pin_dataset_badge_v2.js?v=" + (window.__VSP_ASSET_V || Date.now());
    sc.async=true;
    sc.defer=true;
    (document.head||document.documentElement).appendChild(sc);
  }catch(e){}
})();
''' % marker

# Insert loader near top (after possible 'use strict' or first IIFE)
if loader in s:
    p.write_text(s, encoding="utf-8")
    print("[OK] noop (loader already present)")
else:
    # best-effort insert after first line
    parts=s.splitlines(True)
    parts.insert(1, loader+"\n")
    p.write_text("".join(parts), encoding="utf-8")
    print("[OK] injected loader into", p)
PY
  echo "[OK] injected: $F"
}

inject_loader "static/js/vsp_dashboard_luxe_v1.js"
inject_loader "static/js/vsp_bundle_tabs5_v1.js"
inject_loader "static/js/vsp_tabs4_autorid_v1.js"

# 4) Restart + probe evidence fields
if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] findings_page_v3 (expect data_source + pin_mode fields)"
curl -sS "$BASE/api/vsp/findings_page_v3?rid=VSP_CI_20251218_114312&limit=1&offset=0&pin=auto" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"data_source=",j.get("data_source"),"pin_mode=",j.get("pin_mode"),"from_path=",j.get("from_path"))'

echo "[DONE] Open: $BASE/vsp5?rid=VSP_CI_20251218_114312  then Ctrl+F5"
