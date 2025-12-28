#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need systemctl; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time, textwrap, sys

ROOT = Path("static/js")
cands = []
for p in ROOT.rglob("*.js"):
    if p.name.endswith(".min.js"): 
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if "RunsQuickV1H" in s or "VSP_P1_RUNS_QUICK_ACTIONS" in s:
        cands.append(p)

if not cands:
    # fallback: name heuristic
    for p in ROOT.rglob("vsp_runs*.js"):
        cands.append(p)

cands = sorted(set(cands))
if not cands:
    print("[ERR] cannot locate runs js under static/js")
    sys.exit(2)

target = cands[0]
s = target.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_RUNS_RELEASE_CARD_PATCH_REAL_RUNS_JS_V1"
if mark in s:
    print(f"[OK] already patched: {target}")
    print(target.as_posix())
    sys.exit(0)

bak = target.with_name(target.name + f".bak_releasecard_runs_{time.strftime('%Y%m%d_%H%M%S')}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)

addon = textwrap.dedent(r"""
;(()=> {
  try{
    // ===================== VSP_P1_RUNS_RELEASE_CARD_PATCH_REAL_RUNS_JS_V1 =====================
    const isRuns = ()=>{
      try{
        const p = (location.pathname||"");
        return (p === "/runs" || p.includes("/runs") || p.includes("runs_reports"));
      }catch(e){ return false; }
    };

    function ensureBox(){
      const id="vsp_current_release_card_runs_v1";
      let box=document.getElementById(id);
      if (box) return box;
      box=document.createElement("div");
      box.id=id;
      box.style.cssText=[
        "position:fixed","right:16px","bottom:16px","z-index:99999",
        "max-width:560px","min-width:360px",
        "border:1px solid rgba(255,255,255,.14)",
        "background:rgba(10,18,32,.78)",
        "border-radius:16px","padding:12px 14px",
        "box-shadow:0 12px 34px rgba(0,0,0,.45)",
        "backdrop-filter:blur(8px)"
      ].join(";");
      document.body.appendChild(box);
      return box;
    }

    const row=(k,v)=>`<div style="display:flex;gap:10px;align-items:baseline;line-height:1.35;margin:4px 0">
      <div style="min-width:110px;opacity:.78">${k}</div>
      <div style="font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12.5px; word-break:break-all">${v}</div>
    </div>`;

    async function load(){
      if (!isRuns()) return;
      const box=ensureBox();
      try{
        const r = await fetch("/api/vsp/release_latest", {credentials:"same-origin", cache:"no-store"});
        if (!r.ok) throw new Error("http_"+r.status);
        const j = await r.json();
        if (!j || !j.package) throw new Error("no_package");

        const pkg=j.package, sha=j.sha256_file||"", man=j.manifest||"", ts=j.ts||"";
        box.innerHTML = `
          <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:8px">
            <div style="font-weight:800;letter-spacing:.2px">Current Release</div>
            <div style="opacity:.7;font-size:12px">${ts}</div>
          </div>
          ${row("PACKAGE", `<a href="/${pkg}" style="color:#9ad7ff;text-decoration:none">${pkg}</a>`)}
          ${sha ? row("SHA256", `<a href="/${sha}" style="color:#9ad7ff;text-decoration:none">${sha}</a>`) : ""}
          ${man ? row("MANIFEST", `<a href="/${man}" style="color:#9ad7ff;text-decoration:none">${man}</a>`) : ""}
          <div style="opacity:.55;font-size:11.5px;margin-top:8px">Auto-refresh: 60s • Runs-only</div>
        `;
        try{ console.log("[ReleaseCardRunsV1] shown:", pkg); }catch(e){}
      }catch(e){
        box.innerHTML = `<div style="font-weight:700">Current Release</div>
          <div style="opacity:.75;margin-top:6px">not available</div>
          <div style="opacity:.55;font-size:11.5px;margin-top:8px">(${String(e&&e.message||e)})</div>`;
      }
    }

    function boot(){
      if (!isRuns()) return;
      if (window.__vsp_runs_release_card_realjs_v1) return;
      window.__vsp_runs_release_card_realjs_v1 = true;
      load();
      setInterval(()=>{ try{ load(); }catch(e){} }, 60000);
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
    // ===================== /VSP_P1_RUNS_RELEASE_CARD_PATCH_REAL_RUNS_JS_V1 =====================
  }catch(e){}
})();
""").strip("\n") + "\n"

target.write_text(s + ("\n" if not s.endswith("\n") else "") + addon, encoding="utf-8")
print("[OK] patched target:", target)
print(target.as_posix())
PY

# node syntax check the patched file (auto print path)
TARGET="$(python3 - <<'PY'
from pathlib import Path
import sys
# re-find the patched file quickly
for p in Path("static/js").rglob("*.js"):
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "VSP_P1_RUNS_RELEASE_CARD_PATCH_REAL_RUNS_JS_V1" in s:
        print(p.as_posix()); break
PY
)"

[ -n "${TARGET:-}" ] || { echo "[ERR] cannot resolve patched target"; exit 2; }

node --check "$TARGET"
echo "[OK] node --check $TARGET"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[OK] restarted"

echo "== NOTE =="
echo "Open /runs and hard refresh (Ctrl+Shift+R). Look bottom-right for 'Current Release' card."
