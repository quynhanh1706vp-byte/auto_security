#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p921_js_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need curl; need date
command -v sudo >/dev/null 2>&1 || true

check_js(){
  local f="$1"
  node --check "$f" >/dev/null 2>&1
}

autoroll(){
  local f="$1"
  if check_js "$f"; then
    echo "[OK] js syntax OK: $f" | tee -a "$OUT/summary.txt"
    return 0
  fi
  echo "[WARN] js syntax FAIL: $f" | tee -a "$OUT/summary.txt"
  local okbk=""
  while IFS= read -r bk; do
    if node --check "$bk" >/dev/null 2>&1; then okbk="$bk"; break; fi
  done < <(ls -1t "${f}.bak_"* 2>/dev/null || true)

  [ -n "$okbk" ] || { echo "[FAIL] no good backup for $f" | tee -a "$OUT/summary.txt"; exit 3; }
  cp -f "$okbk" "$f"
  echo "[OK] rollback => $f <= $okbk" | tee -a "$OUT/summary.txt"
  node --check "$f" >/dev/null 2>&1
}

# 1) rollback any broken JS to a backup that passes node --check
autoroll static/js/vsp_c_settings_v1.js
autoroll static/js/vsp_ops_panel_v1.js
# (optional) check some other core files if you want
for f in static/js/vsp_c_sidebar_v1.js static/js/vsp_c_runs_v1.js static/js/vsp_data_source_tab_v3.js; do
  [ -f "$f" ] && node --check "$f" >/dev/null 2>&1 && echo "[OK] js OK: $f" >> "$OUT/summary.txt" || true
done

# 2) ensure Settings page always loads ops panel JS (idempotent)
python3 - <<'PY'
from pathlib import Path
import datetime
F=Path("static/js/vsp_c_settings_v1.js")
s=F.read_text(encoding="utf-8", errors="replace")
tag="P921_SETTINGS_ENSURE_OPS_LOADER_V1"
if tag in s:
    print("[OK] already has", tag)
    raise SystemExit(0)

bk=Path(str(F)+f".bak_p921loader_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}")
bk.write_text(s, encoding="utf-8")
print("[OK] backup =>", bk)

inject = r"""
// P921_SETTINGS_ENSURE_OPS_LOADER_V1
(function(){
  try{
    if (window.__P921_OPS_LOADER__) return;
    window.__P921_OPS_LOADER__ = 1;

    function ensureHost(){
      var id="vsp_ops_panel_host";
      var el=document.getElementById(id);
      if(!el){
        el=document.createElement("div");
        el.id=id;
        el.style.marginTop="12px";
        // mount near bottom of Settings page if possible
        (document.querySelector("#vsp_settings_root") || document.body).appendChild(el);
      }
      return el;
    }

    function loadOnce(src){
      var exists=[...document.scripts].some(s=> (s.src||"").includes(src.split("?")[0]));
      if(exists) return;
      var sc=document.createElement("script");
      sc.src=src + (src.includes("?") ? "&" : "?") + "v=" + Date.now();
      sc.defer=true;
      document.head.appendChild(sc);
    }

    function kick(){
      ensureHost();
      loadOnce("/static/js/vsp_ops_panel_v1.js");
      if(window.VSPOpsPanel && typeof window.VSPOpsPanel.ensureMounted==="function"){
        window.VSPOpsPanel.ensureMounted();
      }
    }

    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", kick);
    else kick();
  }catch(e){}
})();
"""
F.write_text(s + "\n" + inject + "\n", encoding="utf-8")
print("[OK] appended ops loader to settings js")
PY

# 3) restart + quick verify
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

# wait ready
ok=0
for i in $(seq 1 30); do
  if ss -lntp 2>/dev/null | grep -q ':8910'; then
    code="$(curl -sS --noproxy '*' -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 3 "$BASE/api/vsp/healthz" || true)"
    echo "try#$i LISTEN=1 code=$code" | tee -a "$OUT/wait.txt"
    if [ "$code" = "200" ]; then ok=1; break; fi
  else
    echo "try#$i LISTEN=0" | tee -a "$OUT/wait.txt"
  fi
  sleep 1
done
[ "$ok" = "1" ] || { echo "[FAIL] UI not ready"; exit 4; }

# verify the page + APIs
curl -sS -o /dev/null -D "$OUT/settings.hdr" "$BASE/c/settings" || true
curl -sS -o "$OUT/ops_latest.json" "$BASE/api/vsp/ops_latest_v1" || true
echo "[OK] P921 done. Open: $BASE/c/settings (Ctrl+Shift+R)" | tee -a "$OUT/summary.txt"
