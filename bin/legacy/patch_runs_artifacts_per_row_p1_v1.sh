#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_artifacts_row_${TS}" && echo "[BACKUP] $F.bak_artifacts_row_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_RUNS_ARTIFACTS_ROW_P1_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

addon = r'''
/* VSP_RUNS_ARTIFACTS_ROW_P1_V1: per-row artifacts quick-open */
(function(){
  'use strict';

  function normRid(x){
    if(!x) return "";
    return String(x).trim().replace(/^RID:\s*/i,'').replace(/^RUN_/i,'');
  }

  function artUrl(rid, rel){
    return "/api/vsp/run_artifact_raw_v1/" + encodeURIComponent(rid) + "?rel=" + encodeURIComponent(rel);
  }

  // Render small pill buttons (open in new tab)
  window.VSP_RUNS_renderArtifactsPills = function(rid){
    rid = normRid(rid);
    const pills = [
      ["KICS log",  "kics/kics.log"],
      ["KICS json", "kics/kics.json"],
      ["Trivy err", "trivy/trivy.json.err"],
      ["Semgrep",   "semgrep/semgrep.json"],
      ["Gitleaks",  "gitleaks/gitleaks.json"],
      ["Bandit",    "bandit/bandit.json"],
      ["Syft",      "syft/syft.json"],
      ["Grype",     "grype/grype.json"],
      ["CodeQL",    "codeql/codeql.sarif"],
      ["Unified",   "findings_unified.json"],
      ["Effective", "findings_effective.json"],
    ];

    const mk = (label, rel) => (
      '<a class="vsp-pill-btn" target="_blank" rel="noopener" '+
      'href="'+artUrl(rid,rel)+'" '+
      'style="display:inline-flex;align-items:center;gap:6px;margin:2px 6px 2px 0;padding:6px 8px;border-radius:999px;'+
      'border:1px solid rgba(148,163,184,.25);background:rgba(2,6,23,.35);color:#e2e8f0;font-size:12px;text-decoration:none;">'+
      label+'</a>'
    );

    return pills.map(([l,rel])=>mk(l,rel)).join("");
  };

  // Try to patch row HTML after runs table is rendered.
  // We don't assume exact renderer; we do best-effort DOM patching: find each row with data-rid attr.
  function patchTable(){
    const rows = document.querySelectorAll("[data-run-id],[data-rid],tr[data-rid],tr[data-run-id]");
    if(!rows || !rows.length) return;

    rows.forEach((row)=>{
      const rid = normRid(row.getAttribute("data-rid") || row.getAttribute("data-run-id") || "");
      if(!rid) return;
      if(row.querySelector(".vsp-artifacts-cell")) return;

      // place after existing buttons cell if present, else append to row
      const cell = document.createElement("td");
      cell.className = "vsp-artifacts-cell";
      cell.style.cssText = "min-width:420px;max-width:620px;white-space:normal;";
      cell.innerHTML = window.VSP_RUNS_renderArtifactsPills(rid);

      // If it's a <tr>, append cell; else append into row container
      if(row.tagName && row.tagName.toLowerCase()==="tr"){
        row.appendChild(cell);
      }else{
        const div = document.createElement("div");
        div.className="vsp-artifacts-cell";
        div.innerHTML = cell.innerHTML;
        row.appendChild(div);
      }
    });
  }

  // CSS once
  function injectCss(){
    if(document.getElementById("vsp-runs-artifacts-css")) return;
    const st=document.createElement("style");
    st.id="vsp-runs-artifacts-css";
    st.textContent = ".vsp-pill-btn:hover{filter:brightness(1.08);} .vsp-artifacts-cell{padding-top:6px;padding-bottom:6px;}";
    document.head.appendChild(st);
  }

  function boot(){
    injectCss();
    patchTable();
    // keep trying for async table rendering
    let n=0;
    const t=setInterval(()=>{ patchTable(); n++; if(n>20) clearInterval(t); }, 500);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
'''
s = s.rstrip() + "\n\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended artifacts per-row patch")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_runs_artifacts_per_row_p1_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
