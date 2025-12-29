#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p921c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need curl; need date
command -v sudo >/dev/null 2>&1 || true

F="static/js/vsp_c_settings_v1.js"

log(){ echo "$*" | tee -a "$OUT/summary.txt"; }

node_check(){
  node --check "$1" >/dev/null 2>&1
}

dump_check_err(){
  node --check "$1" 2>&1 | head -n 12 | tee -a "$OUT/node_check_err.txt" || true
}

sanitize_inplace(){
  python3 - <<PY
from pathlib import Path
p=Path("$F")
b=p.read_bytes()

b=b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
b=b.replace(b"\x00", b"")
b=b.replace(b"\xef\xbb\xbf", b"")

s=b.decode("utf-8","replace")
s=s.replace("\u2028","\\n").replace("\u2029","\\n").replace("\ufeff","")

clean=[]
for ch in s:
    o=ord(ch)
    if ch in ("\n","\t") or o>=32:
        clean.append(ch)
s="".join(clean)
if not s.endswith("\n"):
    s += "\n"
p.write_text(s, encoding="utf-8")
print("[OK] sanitized")
PY
}

restore_best_backup(){
  # scan all backups of this file, newest first, pick first that passes node --check
  local cand
  for cand in $(ls -1t "${F}".bak_* 2>/dev/null || true); do
    if node_check "$cand"; then
      cp -f "$cand" "$F"
      log "[OK] restored GOOD backup: $cand -> $F"
      return 0
    fi
  done
  return 1
}

write_fallback_min(){
  log "[WARN] no good backup found => write minimal safe settings JS fallback"
  python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_settings_v1.js")
p.write_text(r"""// P921C_SETTINGS_SAFE_FALLBACK (no console error, keep Ops Panel)
(function(){
  "use strict";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function el(tag, cls, txt){
    const e=document.createElement(tag);
    if(cls) e.className=cls;
    if(txt!=null) e.textContent=txt;
    return e;
  }

  function ensureHost(){
    // Try to find existing container in page; if not, attach to body
    let host = qs("#vsp_settings_ops_host");
    if(!host){
      host = el("div", "vsp-card");
      host.id = "vsp_settings_ops_host";
      host.style.marginTop = "14px";
      host.style.padding = "12px";
      host.style.borderRadius = "12px";
      host.style.border = "1px solid rgba(255,255,255,0.06)";
      host.style.background = "rgba(255,255,255,0.03)";
      const title = el("div", "vsp-h", "Ops Status (CIO)");
      title.style.fontWeight = "700";
      title.style.marginBottom = "8px";
      host.appendChild(title);
      (qs("#vsp_main") || qs("main") || qs("#main") || document.body).appendChild(host);
    }
    return host;
  }

  function loadOpsPanelJs(cb){
    const id="vsp_ops_panel_v1";
    if(document.getElementById(id)) return cb && cb();
    const s=document.createElement("script");
    s.id=id;
    s.src="/static/js/vsp_ops_panel_v1.js?v=" + (Date.now());
    s.onload=()=>cb && cb();
    s.onerror=()=>console.warn("[P921C] failed to load ops panel js");
    document.head.appendChild(s);
  }

  function boot(){
    ensureHost();
    loadOpsPanelJs(function(){
      if(window.VSPOpsPanel && typeof window.VSPOpsPanel.ensureMounted==="function"){
        try{ window.VSPOpsPanel.ensureMounted(); }catch(e){ console.warn("[P921C] ops mount err", e); }
      }
    });
    console.log("[P921C] settings fallback booted");
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
""", encoding="utf-8")
print("[OK] wrote fallback settings JS")
PY
}

log "== [P921C] check js =="
if [ ! -f "$F" ]; then
  log "[ERR] missing $F"
  exit 2
fi

if node_check "$F"; then
  log "[OK] already syntax OK: $F"
else
  log "[WARN] syntax FAIL: $F"
  cp -f "$F" "${F}.bak_p921c_bad_${TS}"
  dump_check_err "$F"
  log "== sanitize =="
  sanitize_inplace
  if node_check "$F"; then
    log "[OK] sanitize fixed syntax"
  else
    log "[WARN] sanitize still FAIL => try restore backup"
    if restore_best_backup; then
      :
    else
      write_fallback_min
      node_check "$F" || { log "[ERR] fallback still FAIL (unexpected)"; dump_check_err "$F"; exit 3; }
    fi
  fi
fi

log "== restart service =="
sudo systemctl restart "$SVC" || true

log "== wait ready =="
ok=0
for i in $(seq 1 30); do
  code="$(curl -sS --noproxy '*' -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/api/vsp/healthz" || true)"
  echo "try#$i code=$code" | tee -a "$OUT/wait.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done
[ "$ok" = "1" ] || { log "[FAIL] UI not ready"; exit 4; }

log "== smoke =="
bash bin/p918_p0_smoke_no_error_v1.sh | tee -a "$OUT/smoke.txt"

log "[OK] P921C done. Open: $BASE/c/settings (Ctrl+Shift+R) and check console."
log "[OK] Evidence: $OUT"
