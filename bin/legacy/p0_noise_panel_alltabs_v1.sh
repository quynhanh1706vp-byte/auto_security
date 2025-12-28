#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
FILES=(static/js/vsp_tabs3_common_v3.js static/js/vsp_ui_shell_v1.js)

echo "== [0] pick targets =="
TARGETS=()
for f in "${FILES[@]}"; do
  [ -f "$f" ] && TARGETS+=("$f")
done
[ "${#TARGETS[@]}" -gt 0 ] || { echo "[ERR] no target js found"; exit 2; }
printf "%s\n" "${TARGETS[@]}" | sed 's/^/[OK] /'

echo "== [1] backup =="
for f in "${TARGETS[@]}"; do
  cp -f "$f" "${f}.bak_noisepanel_${TS}"
  echo "[BACKUP] ${f}.bak_noisepanel_${TS}"
done

echo "== [2] inject noise panel (idempotent) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap

marker = "VSP_NOISE_PANEL_ALLTABS_V1"
inject = textwrap.dedent(r"""
/* VSP_NOISE_PANEL_ALLTABS_V1
   Alt+N: toggle panel
   Alt+Shift+N: clear log
*/
(()=> {
  try {
    if (window.__vsp_noise_panel_alltabs_v1) return;
    window.__vsp_noise_panel_alltabs_v1 = true;

    const KEY = "vsp_noise_log_v1";
    const MAX = 300;

    function now(){ return new Date().toISOString(); }
    function load(){
      try { return JSON.parse(localStorage.getItem(KEY) || "[]"); } catch(e){ return []; }
    }
    function save(arr){
      try { localStorage.setItem(KEY, JSON.stringify(arr.slice(-MAX))); } catch(e){}
    }
    function push(item){
      const arr = load();
      arr.push(item);
      save(arr);
    }
    function clear(){
      try { localStorage.removeItem(KEY); } catch(e){}
    }

    function record(kind, data){
      push({
        t: now(),
        tab: location.pathname,
        kind,
        ...data
      });
    }

    // fetch hook
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (_fetch){
      window.fetch = async function(input, init){
        const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        try{
          const res = await _fetch(input, init);
          if (!res.ok){
            record("fetch", {status: res.status, url});
          }
          return res;
        }catch(e){
          record("fetch_exc", {status: 0, url, err: String(e && e.message || e)});
          throw e;
        }
      };
    }

    // XHR hook
    const XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype && XHR.prototype.open){
      const _open = XHR.prototype.open;
      const _send = XHR.prototype.send;
      XHR.prototype.open = function(method, url){
        this.__vsp_url = (typeof url === "string") ? url : "";
        return _open.apply(this, arguments);
      };
      XHR.prototype.send = function(){
        try{
          this.addEventListener("loadend", ()=>{
            try{
              const st = this.status || 0;
              if (st >= 400 || st === 0){
                record("xhr", {status: st, url: this.__vsp_url || ""});
              }
            }catch(e){}
          });
        }catch(e){}
        return _send.apply(this, arguments);
      };
    }

    // JS errors
    window.addEventListener("error", (ev)=>{
      try{
        record("js_error", {msg: String(ev.message||""), src: String(ev.filename||""), line: ev.lineno||0, col: ev.colno||0});
      }catch(e){}
    });

    window.addEventListener("unhandledrejection", (ev)=>{
      try{
        record("promise_rej", {msg: String(ev.reason && (ev.reason.message||ev.reason) || "unhandled")});
      }catch(e){}
    });

    // Panel UI
    function ensurePanel(){
      if (document.getElementById("vspNoisePanelV1")) return;
      const d = document.createElement("div");
      d.id = "vspNoisePanelV1";
      d.style.cssText = "position:fixed;right:12px;bottom:12px;z-index:999999;background:rgba(0,0,0,.85);color:#d6e0ff;border:1px solid rgba(255,255,255,.15);border-radius:12px;width:520px;max-height:60vh;overflow:auto;font:12px/1.4 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;box-shadow:0 12px 30px rgba(0,0,0,.35);display:none;";
      d.innerHTML = `
        <div style="padding:10px 10px 6px;display:flex;gap:8px;align-items:center;position:sticky;top:0;background:rgba(0,0,0,.9);">
          <div style="font-weight:700">VSP Noise</div>
          <div style="opacity:.7">Alt+N toggle • Alt+Shift+N clear</div>
          <div style="margin-left:auto;display:flex;gap:6px">
            <button id="vspNoiseRefreshV1" style="all:unset;cursor:pointer;padding:4px 8px;border:1px solid rgba(255,255,255,.2);border-radius:8px;">Refresh</button>
            <button id="vspNoiseClearV1" style="all:unset;cursor:pointer;padding:4px 8px;border:1px solid rgba(255,255,255,.2);border-radius:8px;">Clear</button>
          </div>
        </div>
        <div id="vspNoiseBodyV1" style="padding:8px 10px 10px;"></div>
      `;
      document.body.appendChild(d);
      document.getElementById("vspNoiseRefreshV1").onclick = render;
      document.getElementById("vspNoiseClearV1").onclick = ()=>{ clear(); render(); };
      render();
    }

    function render(){
      ensurePanel();
      const body = document.getElementById("vspNoiseBodyV1");
      const arr = load().slice().reverse();
      if (!arr.length){
        body.innerHTML = `<div style="opacity:.7">No noise 🎉</div>`;
        return;
      }
      body.innerHTML = arr.map(x=>{
        const u = (x.url||"").replace(location.origin,"");
        return `<div style="padding:6px 0;border-bottom:1px dashed rgba(255,255,255,.12)">
          <div><b>${x.kind}</b> <span style="opacity:.7">${x.t}</span> <span style="opacity:.7">(${x.tab})</span></div>
          ${x.status!==undefined?`<div>status: <b>${x.status}</b></div>`:""}
          ${u?`<div style="word-break:break-all">url: ${u}</div>`:""}
          ${x.msg?`<div style="word-break:break-word">msg: ${String(x.msg).slice(0,200)}</div>`:""}
        </div>`;
      }).join("");
    }

    function toggle(){
      ensurePanel();
      const el = document.getElementById("vspNoisePanelV1");
      el.style.display = (el.style.display === "none") ? "block" : "none";
      if (el.style.display === "block") render();
    }

    window.__vsp_noise = {render, toggle, clear};

    window.addEventListener("keydown", (ev)=>{
      if (ev.altKey && !ev.shiftKey && (ev.key==="n" || ev.key==="N")) { ev.preventDefault(); toggle(); }
      if (ev.altKey && ev.shiftKey && (ev.key==="n" || ev.key==="N")) { ev.preventDefault(); clear(); render(); }
    }, {passive:false});

  } catch(e) {}
})();
""")

def patch(path: Path):
    s = path.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[INFO] already:", path); return False
    m = re.search(r'(\(\s*\)\s*=>\s*\{\s*)', s)
    if m:
        pos = m.end()
        s2 = s[:pos] + "\n" + inject + "\n" + s[pos:]
    else:
        s2 = inject + "\n" + s
    path.write_text(s2, encoding="utf-8")
    print("[OK] patched:", path)
    return True

changed = 0
for fp in ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_ui_shell_v1.js"]:
    p = Path(fp)
    if p.exists():
        if patch(p): changed += 1

print("[DONE] changed:", changed)
PY

echo "== [3] node --check =="
for f in "${TARGETS[@]}"; do
  node --check "$f" >/dev/null && echo "[OK] node --check: $f"
done

echo "[DONE] Ctrl+F5. Press Alt+N on ANY tab to see all noise. Alt+Shift+N to clear."
