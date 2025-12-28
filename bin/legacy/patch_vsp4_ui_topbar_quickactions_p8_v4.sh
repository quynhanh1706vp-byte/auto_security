#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_UI_TOPBAR_QUICKACTIONS_P8_V4"

echo "== PATCH UI TOPBAR P8.V4 =="
echo "[TS]=$TS"
echo "[BASE]=$BASE"

# pick templates likely serving /vsp4
mapfile -t CANDS < <(
  { grep -rl --include='*.html' 'Route: <span class="vsp-mono">/vsp4</span>' templates 2>/dev/null || true; \
    grep -rl --include='*.html' 'vsp_bundle_commercial_v2.js' templates 2>/dev/null || true; } \
  | awk '!x[$0]++'
)

# force include known ones if exist
[ -f templates/vsp_4tabs_commercial_v1.html ] && CANDS+=("templates/vsp_4tabs_commercial_v1.html")
[ -f templates/vsp_5tabs_enterprise_v2.html ] && CANDS+=("templates/vsp_5tabs_enterprise_v2.html")

# unique + existing
CANDS=($(printf "%s\n" "${CANDS[@]}" | awk '!x[$0]++' | while read -r f; do [ -f "$f" ] && echo "$f"; done))
[ ${#CANDS[@]} -gt 0 ] || { echo "[ERR] cannot find templates to patch"; exit 2; }

echo "[FILES]=${#CANDS[@]}"
printf " - %s\n" "${CANDS[@]}"

export P8_FILES="$(printf "%s\n" "${CANDS[@]}")"

python3 - <<'PY'
import os, re
from pathlib import Path

MARK="VSP_UI_TOPBAR_QUICKACTIONS_P8_V4"

BLOCK = r"""
<!-- VSP_UI_TOPBAR_QUICKACTIONS_P8_V4 BEGIN -->
<style id="vspTopbarCssP8v4">
  #vspTopbarP8v4{
    position:fixed; top:0; left:0; right:0; height:52px;
    display:flex; align-items:center; justify-content:space-between;
    padding:0 14px; z-index:99999;
    background:rgba(10,14,24,.92);
    border-bottom:1px solid rgba(255,255,255,.08);
    backdrop-filter: blur(8px);
  }
  #vspTopbarP8v4 .l{display:flex; gap:10px; align-items:center; min-width:260px;}
  #vspTopbarP8v4 .r{display:flex; gap:8px; align-items:center;}
  #vspTopbarP8v4 .brand{font-weight:700; letter-spacing:.3px; font-size:14px; color:#e8eefc;}
  #vspTopbarP8v4 .chip{
    font-size:12px; padding:4px 8px; border-radius:999px;
    border:1px solid rgba(255,255,255,.10);
    color:rgba(232,238,252,.92);
    background:rgba(255,255,255,.04);
    white-space:nowrap;
  }
  #vspTopbarP8v4 .btn{
    font-size:12px; padding:7px 10px; border-radius:10px;
    border:1px solid rgba(255,255,255,.12);
    background:rgba(255,255,255,.06);
    color:#eef3ff; cursor:pointer;
  }
  #vspTopbarP8v4 .btn:hover{ background:rgba(255,255,255,.10); }
  body{ padding-top:52px !important; }
</style>

<div id="vspTopbarP8v4">
  <div class="l">
    <div class="brand">VersaSecure Platform — Commercial</div>
    <div class="chip" id="vspChipIsoP8v4">ISO 27001-ready</div>
    <div class="chip" id="vspChipToolsP8v4">8 tools</div>
    <div class="chip" id="vspChipDegradedP8v4">DEGRADED: …</div>
  </div>
  <div class="r">
    <button class="btn" id="vspBtnRefreshP8v4">Refresh</button>
    <button class="btn" id="vspBtnOpenHtmlP8v4">Open HTML</button>
    <button class="btn" id="vspBtnExportTgzP8v4">Export TGZ</button>
    <button class="btn" id="vspBtnVerifyShaP8v4">Verify SHA</button>
  </div>
</div>

<script id="vspTopbarJsP8v4">
(function(){
  if (window.__VSP_UI_TOPBAR_QUICKACTIONS_P8_V4) return;
  window.__VSP_UI_TOPBAR_QUICKACTIONS_P8_V4 = true;

  function norm(s){ return (s||"").replace(/\s+/g," ").trim().toLowerCase(); }
  function clickBtnContains(part){
    const want = norm(part);
    const btns = Array.from(document.querySelectorAll("button,a"));
    for (const b of btns){
      const t = norm(b.innerText || b.textContent || "");
      if (!t) continue;
      if (t.includes(want)){ b.click(); return true; }
    }
    return false;
  }
  const $ = (id)=>document.getElementById(id);

  $("vspBtnRefreshP8v4").onclick = function(){
    if (clickBtnContains("refresh")) return;
    location.reload();
  };
  $("vspBtnOpenHtmlP8v4").onclick = function(){
    if (clickBtnContains("open html")) return;
    alert("Open HTML button not found on this tab. Try Runs & Reports, then retry.");
  };
  $("vspBtnExportTgzP8v4").onclick = function(){
    if (clickBtnContains("export tgz")) return;
    alert("Export TGZ button not found on this tab. Try Runs & Reports, then retry.");
  };
  $("vspBtnVerifyShaP8v4").onclick = function(){
    if (clickBtnContains("verify sha")) return;
    alert("Verify SHA button not found on this tab. Try Runs & Reports, then retry.");
  };

  function updateDegraded(){
    fetch("/api/vsp/dashboard_commercial_v2?ts=" + Date.now())
      .then(r=>r.json())
      .then(j=>{
        const yes = !!(((j||{}).overall||{}).degraded_yes);
        $("vspChipDegradedP8v4").textContent = "DEGRADED: " + (yes ? "YES" : "NO");
      })
      .catch(()=>{ $("vspChipDegradedP8v4").textContent = "DEGRADED: N/A"; });
  }
  updateDegraded();
  setInterval(updateDegraded, 15000);
})();
</script>
<!-- VSP_UI_TOPBAR_QUICKACTIONS_P8_V4 END -->
"""

def inject_after_body_open(html: str) -> str:
    m = re.search(r"<body\b[^>]*>", html, flags=re.IGNORECASE)
    if not m:
        return html + "\n" + BLOCK + "\n<!-- " + MARK + " -->\n"
    i = m.end()
    return html[:i] + "\n" + BLOCK + "\n" + html[i:] + "\n<!-- " + MARK + " -->\n"

files = [x.strip() for x in os.environ.get("P8_FILES","").splitlines() if x.strip()]
patched = 0
for f in files:
    p = Path(f)
    if not p.exists(): 
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[SKIP] already:", p); 
        continue
    # backup
    b = p.with_suffix(p.suffix + f".bak_p8v4_{os.environ.get('TS','')}".rstrip("_"))
    try:
        b.write_text(s, encoding="utf-8")
        print("[BACKUP]", b)
    except Exception:
        pass
    p.write_text(inject_after_body_open(s), encoding="utf-8")
    print("[OK] patched:", p)
    patched += 1

print("[DONE] patched_files=", patched)
PY

echo "== HARD RESET 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "== SMOKE =="
curl -sS -m 4 -o /dev/null -w '[HTTP] %{http_code} /vsp4\n' "$BASE/vsp4" || true

echo "[NEXT] Ctrl+Shift+R http://127.0.0.1:8910/vsp4  (TopBar phải hiện ngay)"
