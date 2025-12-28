#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p467d_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

F="static/js/vsp_c_runs_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - "$F" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P467D_HIDE_LEGACY_RUNS_GLOBAL_V1"
if MARK in s:
    print("[OK] already patched P467d")
    raise SystemExit(0)

addon=r"""
/* --- VSP_P467D_HIDE_LEGACY_RUNS_GLOBAL_V1 --- */
(function(){
  if(window.__VSP_P467D_ON) return;
  window.__VSP_P467D_ON = true;

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function txt(el){ return (el && el.textContent ? el.textContent : ""); }

  function ensureCss(){
    if(qs("#vsp_p467d_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p467d_css";
    st.textContent = `.vsp-p467d-hide{ display:none !important; }`;
    document.head.appendChild(st);
  }

  function isInside(el, container){
    try{ return container && el && container.contains(el); }catch(e){ return false; }
  }

  // Heuristics nhận diện "bản cũ" (legacy):
  // - có header "LABEL/TS" hoặc chuỗi "Dashboard CSV Reports.tgz Use RID"
  // - hoặc có combo "Reports.tgz" + "Use RID" + "Dashboard" + "CSV"
  function looksLegacyText(t){
    t = String(t||"").toLowerCase();
    if(t.includes("label/ts")) return true;
    if(t.includes("dashboard") && t.includes("reports.tgz") && t.includes("use rid") && t.includes("csv")) return true;
    if(t.includes("runs & reports") && t.includes("filter by rid") && t.includes("client-side")) return true;
    return false;
  }

  function hideLegacyOnce(){
    ensureCss();

    // mount của Runs Pro (đừng đụng vào)
    const proMount =
      qs("#vsp_runs_pro_mount_c_runs") ||
      qs("#vsp_runs_pro_mount_c") ||
      qs("#vsp_p464c_exports_mount"); // mount exports cũng không phải legacy list, nhưng vẫn giữ

    // 1) Hide any legacy TABLE
    const tables = qsa("table");
    for(const tb of tables){
      if(isInside(tb, proMount)) continue;

      const headText = txt(tb).slice(0, 2000);
      if(looksLegacyText(headText)){
        tb.classList.add("vsp-p467d-hide");
        continue;
      }

      // check rows for legacy action signature
      const t = txt(tb).toLowerCase();
      if(t.includes("reports.tgz") && t.includes("use rid") && t.includes("dashboard") && t.includes("csv")){
        tb.classList.add("vsp-p467d-hide");
      }
    }

    // 2) Hide legacy blocks (div/section) chứa “bảng cũ” nhưng không phải table trực tiếp
    const blocks = qsa("section,div");
    for(const b of blocks){
      if(isInside(b, proMount)) continue;

      const t = txt(b);
      if(!t) continue;

      // tránh hide nhầm container quá lớn (body)
      if(b === document.body || b === document.documentElement) continue;

      if(looksLegacyText(t)){
        // chỉ hide nếu block này có dấu hiệu là 1 card/table container
        // ví dụ: có nhiều "Reports.tgz" hoặc có "RID" lặp nhiều lần
        const tl = t.toLowerCase();
        const score =
          (tl.split("reports.tgz").length-1) +
          (tl.split("use rid").length-1) +
          (tl.split("dashboard").length-1) +
          (tl.split("csv").length-1);

        if(score >= 2 || tl.includes("label/ts")){
          b.classList.add("vsp-p467d-hide");
        }
      }
    }

    // 3) Extra: legacy header bar “Runs & Reports (real list from /api/vsp/runs)” nếu còn
    qsa("*").forEach(el=>{
      if(isInside(el, proMount)) return;
      const t = txt(el).trim().toLowerCase();
      if(t === "runs & reports (real list from /api/vsp/runs)"){
        const wrap = el.closest("div,section") || el;
        wrap.classList.add("vsp-p467d-hide");
      }
    });
  }

  function boot(){
    try{ hideLegacyOnce(); }catch(e){}
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  // chạy lại vài lần để bắt trường hợp render async
  setTimeout(boot, 300);
  setTimeout(boot, 900);
  setTimeout(boot, 1600);

  console.log("[P467d] legacy runs table hidden globally (safe)");
})();
 /* --- /VSP_P467D_HIDE_LEGACY_RUNS_GLOBAL_V1 --- */
"""

p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P467d addon into vsp_c_runs_v1.js")
PY

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P467d done. Hard refresh /c/runs (Ctrl+Shift+R). Expect: legacy table at bottom is hidden." | tee -a "$OUT/log.txt"
