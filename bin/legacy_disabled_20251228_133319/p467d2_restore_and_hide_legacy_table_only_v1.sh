#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p467d2_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

F="static/js/vsp_c_runs_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

# 1) restore from latest p467d backup if exists (best)
BK="$(ls -1t out_ci/p467d_*/vsp_c_runs_v1.js.bak_* 2>/dev/null | head -n1 || true)"
if [ -n "${BK:-}" ] && [ -f "$BK" ]; then
  cp -f "$BK" "$F"
  echo "[OK] restored $F <= $BK" | tee -a "$OUT/log.txt"
else
  echo "[WARN] no p467d backup found; will try to remove P467d block in-place" | tee -a "$OUT/log.txt"
  python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
# remove P467d block if present
start = s.find("VSP_P467D_HIDE_LEGACY_RUNS_GLOBAL_V1")
if start!=-1:
    # try cut from the comment begin
    a = s.rfind("/*", 0, start)
    b = s.find("/* --- /VSP_P467D_HIDE_LEGACY_RUNS_GLOBAL_V1 --- */", start)
    if a!=-1 and b!=-1:
        b2 = b + len("/* --- /VSP_P467D_HIDE_LEGACY_RUNS_GLOBAL_V1 --- */")
        s = s[:a] + "\n\n" + s[b2:]  # drop the whole block
p.write_text(s, encoding="utf-8")
print("[OK] in-place cleanup attempt done")
PY
fi

cp -f "$F" "$OUT/$(basename "$F").bak_before_${TS}"
echo "[OK] snapshot before P467d2 => $OUT/$(basename "$F").bak_before_${TS}" | tee -a "$OUT/log.txt"

# 2) append safer hide-legacy logic: TABLE-ONLY (no div/section nuking)
python3 - "$F" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P467D2_HIDE_LEGACY_TABLE_ONLY_V1"
if MARK in s:
    print("[OK] already patched P467d2")
    raise SystemExit(0)

addon=r"""
/* --- VSP_P467D2_HIDE_LEGACY_TABLE_ONLY_V1 --- */
(function(){
  if(window.__VSP_P467D2_ON) return;
  window.__VSP_P467D2_ON = true;

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function txt(el){ return (el && el.textContent) ? el.textContent : ""; }

  function ensureCss(){
    if(qs("#vsp_p467d2_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p467d2_css";
    st.textContent = `.vsp-p467d2-hide{ display:none !important; }`;
    document.head.appendChild(st);
  }

  function looksLegacyTableText(t){
    t = String(t||"").toLowerCase();
    // signature của bảng cũ
    if(t.includes("label/ts")) return true;
    if(t.includes("filter by rid") && t.includes("client-side")) return true;
    if(t.includes("reports.tgz") && t.includes("use rid") && t.includes("dashboard") && t.includes("csv")) return true;
    return false;
  }

  function hideLegacyTables(){
    ensureCss();

    // giữ nguyên Runs Pro mount (nếu có)
    const proMount =
      qs("#vsp_runs_pro_mount_c_runs") ||
      qs("#vsp_runs_pro_mount_c") ||
      qs("#vsp_runs_pro_mount") ||
      qs("#vsp_p464c_exports_mount");

    const tables=qsa("table");
    let hidden=0;
    for(const tb of tables){
      if(proMount && proMount.contains(tb)) continue;
      const t = txt(tb).slice(0, 3000);
      if(looksLegacyTableText(t)){
        tb.classList.add("vsp-p467d2-hide");
        hidden++;
        // thường bảng nằm trong card wrapper: chỉ hide wrapper nếu wrapper cực nhỏ & rõ ràng là card bảng
        const wrap = tb.closest(".card,.panel,.box,.container,.vsp-card") || null;
        if(wrap && wrap !== document.body && wrap !== document.documentElement){
          // tránh hide nhầm wrapper lớn: chỉ hide nếu wrapper không chứa proMount
          if(!(proMount && wrap.contains(proMount))){
            // wrapper phải chứa chính table đó và không quá nhiều text ngoài
            const wt = txt(wrap).toLowerCase()
            if(wt.count("reports.tgz") >= 1 or "label/ts" in wt):
              pass
          }
        }
      }
    }

    // đảm bảo proMount nếu có thì luôn hiện
    if(proMount) proMount.style.display = "block";

    console.log("[P467d2] legacy tables hidden=", hidden);
  }

  function boot(){
    try{ hideLegacyTables(); }catch(e){ console.warn("[P467d2] hide fail", e); }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  // async render safety
  setTimeout(boot, 300);
  setTimeout(boot, 900);
  setTimeout(boot, 1600);
})();
 /* --- /VSP_P467D2_HIDE_LEGACY_TABLE_ONLY_V1 --- */
"""

# NOTE: Không đụng vào code cũ, chỉ append addon.
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P467d2 addon")
PY

# 3) restart
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P467d2 done. Hard refresh /c/runs (Ctrl+Shift+R). Expect: Runs Pro hiện lại, bảng cũ bị ẩn." | tee -a "$OUT/log.txt"
