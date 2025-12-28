#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_sidebar_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p480_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p480_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_sidebar_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P480_SETTINGS_CIO_DOCS_NO_RUN_V1"
if MARK in s:
    print("[OK] already patched P480")
else:
    add=r"""

/* VSP_P480_SETTINGS_CIO_DOCS_NO_RUN_V1 */
(function(){
  if (window.__VSP_P480__) return;
  window.__VSP_P480__ = 1;

  // hard policy: no demo in commercial build
  try{ localStorage.removeItem("VSP_DEMO_RUNS"); }catch(e){}

  function ensureCss(){
    if(document.getElementById("vsp_p480_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p480_css";
    st.textContent=`
#vsp_p480_docs{
  margin:14px 0;
  padding:16px 16px;
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
}
#vsp_p480_docs .h{
  display:flex;align-items:flex-start;justify-content:space-between;gap:12px;
}
#vsp_p480_docs .t{font-weight:900;font-size:14px;letter-spacing:.25px}
#vsp_p480_docs .sub{opacity:.75;font-size:12px;margin-top:2px;line-height:1.5}
#vsp_p480_docs details{
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
  border-radius:14px;
  padding:10px 12px;
  margin-top:10px;
}
#vsp_p480_docs summary{
  cursor:pointer;
  user-select:none;
  font-weight:800;
  letter-spacing:.2px;
}
#vsp_p480_docs .p{
  margin-top:8px;
  opacity:.88;
  font-size:12px;
  line-height:1.6;
}
#vsp_p480_docs code{
  background:rgba(0,0,0,0.25);
  border:1px solid rgba(255,255,255,0.08);
  padding:2px 6px;
  border-radius:8px;
}
#vsp_p480_docs .grid{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:10px;
  margin-top:10px;
}
@media (max-width: 1100px){
  #vsp_p480_docs .grid{grid-template-columns:1fr}
}
#vsp_p480_docs .k{
  border:1px solid rgba(255,255,255,0.06);
  border-radius:14px;
  padding:10px 12px;
  background:rgba(255,255,255,0.02);
}
#vsp_p480_docs .k .kt{font-weight:900;font-size:12px;opacity:.95}
#vsp_p480_docs .k .kd{margin-top:6px;opacity:.82;font-size:12px;line-height:1.55}
`;
    document.head.appendChild(st);
  }

  function mountDocs(){
    if(!location.pathname.includes("/c/settings")) return;

    ensureCss();

    const root = document.querySelector(".vsp_p473_frame") || document.getElementById("vsp_p473_wrap") || document.body;
    if(!root) return;

    if(document.getElementById("vsp_p480_docs")) return;

    const box=document.createElement("div");
    box.id="vsp_p480_docs";

    const head=document.createElement("div");
    head.className="h";
    const L=document.createElement("div");
    const t=document.createElement("div"); t.className="t"; t.textContent="Settings • Commercial Playbook (CIO/ISO-ready)";
    const sub=document.createElement("div");
    sub.className="sub";
    sub.innerHTML="Chuẩn thương mại: cấu hình, hành vi degraded/timeout, chuẩn severity 6 mức, và mapping ISO 27001.<br/>Không dùng DEMO — chỉ dữ liệu thật từ pipeline.";
    L.appendChild(t); L.appendChild(sub);

    head.appendChild(L);
    box.appendChild(head);

    // 1) Tools overview
    const d1=document.createElement("details"); d1.open=true;
    d1.innerHTML = `
<summary>8-tool suite & artifacts</summary>
<div class="p">
  Pipeline mặc định gồm: <b>Bandit</b>, <b>Semgrep</b>, <b>Gitleaks</b>, <b>KICS</b>, <b>Trivy</b>, <b>Syft</b>, <b>Grype</b>, <b>CodeQL</b>.
  Mỗi tool phải tạo raw output + summary, sau đó merge ra <code>findings_unified.{json,csv,sarif}</code> và <code>run_gate_summary.json</code>.
</div>
<div class="grid">
  <div class="k"><div class="kt">Bandit (SAST-Python)</div><div class="kd">Scan code Python. Output: JSON/text. Map severity → 6 levels.</div></div>
  <div class="k"><div class="kt">Semgrep (SAST)</div><div class="kd">Ruleset + custom overrides. Output: JSON/SARIF.</div></div>
  <div class="k"><div class="kt">Gitleaks (Secrets)</div><div class="kd">Secrets in repo. Output: JSON. Gate thường HIGH/CRITICAL.</div></div>
  <div class="k"><div class="kt">KICS (IaC)</div><div class="kd">Terraform/K8s/IaC misconfig. Output: JSON/SARIF. Cần timeout + degraded-graceful.</div></div>
  <div class="k"><div class="kt">Trivy (Vuln scan)</div><div class="kd">Config/SBOM/containers. Output: JSON. Nên normalize CVSS/severity.</div></div>
  <div class="k"><div class="kt">Syft (SBOM)</div><div class="kd">Generate SBOM. Output: JSON. Input cho Grype.</div></div>
  <div class="k"><div class="kt">Grype (SCA)</div><div class="kd">Vulnerability from SBOM. Output: JSON. Gate theo severity normalized.</div></div>
  <div class="k"><div class="kt">CodeQL (Deep SAST)</div><div class="kd">Chạy lâu → bắt buộc timeout + degraded status nếu thiếu tool/index.</div></div>
</div>
`;
    box.appendChild(d1);

    // 2) Degraded / timeout policy
    const d2=document.createElement("details");
    d2.innerHTML = `
<summary>Degraded / Timeout policy (commercial)</summary>
<div class="p">
  Nguyên tắc: pipeline <b>không được treo</b>. Tool thiếu/timeout → đánh dấu <b>DEGRADED</b> và vẫn xuất report + evidence.
  Ví dụ: KICS/CodeQL timeout thì status tool = degraded, tổng run vẫn có <code>run_status_v1</code> + <code>SUMMARY.txt</code>.
</div>
<div class="p">
  Checklist:
  <ul>
    <li>Mỗi tool có <code>timeout</code> wrapper.</li>
    <li>Missing binary → degraded (không crash cả pipeline).</li>
    <li>Log path rõ ràng + tail parser cập nhật <code>run_status_v1</code>.</li>
    <li>Artifacts tối thiểu: raw + summary + stdout/stderr + timestamps.</li>
  </ul>
</div>
`;
    box.appendChild(d2);

    // 3) Severity normalization
    const d3=document.createElement("details");
    d3.innerHTML = `
<summary>Severity normalization (6 DevSecOps levels)</summary>
<div class="p">
  Chuẩn hoá severity bắt buộc đúng 6 mức: <b>CRITICAL</b>, <b>HIGH</b>, <b>MEDIUM</b>, <b>LOW</b>, <b>INFO</b>, <b>TRACE</b>.
  Mọi findings từ tools phải map về đúng 6 mức này trước khi merge.
</div>
<div class="p">
  Gợi ý rule:
  <ul>
    <li>CVSS ≥ 9.0 → CRITICAL</li>
    <li>7.0–8.9 → HIGH</li>
    <li>4.0–6.9 → MEDIUM</li>
    <li>0.1–3.9 → LOW</li>
    <li>informational → INFO</li>
    <li>noise/telemetry → TRACE</li>
  </ul>
</div>
`;
    box.appendChild(d3);

    // 4) ISO 27001 mapping skeleton
    const d4=document.createElement("details");
    d4.innerHTML = `
<summary>ISO 27001 mapping (skeleton)</summary>
<div class="p">
  Mapping dùng để chứng minh tuân thủ: findings → control family. Tối thiểu nên map:
  <ul>
    <li>Secrets / key management → A.5 / A.8 (tuỳ phiên bản control set)</li>
    <li>Vuln management / patching → A.8</li>
    <li>Secure development / SDLC controls → A.8</li>
    <li>Access control issues → A.5</li>
    <li>Logging/monitoring gaps → A.8</li>
  </ul>
  (Tuỳ bộ ISO 27001:2022 control list nội bộ của bạn, mình sẽ “đóng khung mapping” chuẩn theo danh mục control của công ty.)
</div>
`;
    box.appendChild(d4);

    // insert after titlebar if possible
    const tb=document.getElementById("vsp_p474_titlebar");
    if(tb && tb.parentNode) tb.parentNode.insertBefore(box, tb.nextSibling);
    else root.insertBefore(box, root.firstChild);

    console && console.log && console.log("[P480] settings CIO docs mounted");
  }

  function boot(){
    // mount a bit later (settings page sometimes renders async)
    setTimeout(mountDocs, 250);
    setTimeout(mountDocs, 900);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
    p.write_text(s + add, encoding="utf-8")
    print("[OK] patched P480 into vsp_c_sidebar_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 || { echo "[ERR] node check failed: $F" | tee -a "$OUT/log.txt"; exit 2; }
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P480 done. Reopen /c/settings then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
