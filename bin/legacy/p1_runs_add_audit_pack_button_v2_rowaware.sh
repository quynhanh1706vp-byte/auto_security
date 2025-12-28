#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_auditbtn_v2_${TS}"
echo "[BACKUP] ${JS}.bak_auditbtn_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUNS_AUDIT_PACK_BTN_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = textwrap.dedent(r"""
/* ===================== VSP_P1_RUNS_AUDIT_PACK_BTN_V2 ===================== */
(()=> {
  if (window.__vsp_p1_runs_audit_pack_btn_v2) return;
  window.__vsp_p1_runs_audit_pack_btn_v2 = true;

  const qsa = (sel, root)=>{ try { return Array.from((root||document).querySelectorAll(sel)); } catch(e){ return []; } };
  const txt = (el)=> (el && el.textContent ? el.textContent.trim() : "");

  function btnByText(root, label){
    const bs = qsa("button,a", root);
    label = (label||"").toLowerCase();
    for (const b of bs){
      const t = txt(b).toLowerCase();
      if (t === label) return b;
    }
    return null;
  }

  function hasAuditBtn(root){
    const bs = qsa("button,a", root);
    for (const b of bs){
      if (txt(b).toLowerCase() === "audit pack") return true;
    }
    return false;
  }

  function extractRidFromText(s){
    if (!s) return "";
    // patterns seen in your UI:
    // dmpw_linux_install_v8_RUN_20251217_124437_699896
    // RUN_VSP_KICS_TEST_20251211_161546
    // VSP_CI_20251218_114312
    const patterns = [
      /([A-Za-z0-9_-]+_RUN_\d{8}_\d{6,}(?:_\d+)*)/,
      /(RUN_[A-Za-z0-9_]+_\d{8}_\d{6,}(?:_\d+)*)/,
      /(VSP_CI_RUN_\d{8}_\d{6,})/,
      /(VSP_CI_\d{8}_\d{6,})/,
      /(RUN_\d{8}_\d{6,}(?:_\d+)*)/,
    ];
    for (const re of patterns){
      const m = s.match(re);
      if (m && m[1]) return m[1].trim();
    }
    return "";
  }

  function findRowContainerFromCopyBtn(copyBtn){
    // climb a few levels until container also contains TGZ/CSV buttons
    let cur = copyBtn;
    for (let i=0; i<8; i++){
      if (!cur) break;
      const tgz = btnByText(cur, "TGZ");
      const csv = btnByText(cur, "CSV");
      if (tgz && csv) return cur;
      cur = cur.parentElement;
    }
    return null;
  }

  function ensureAuditOnRow(row){
    if (!row || hasAuditBtn(row)) return;

    const tgzBtn = btnByText(row, "TGZ");
    if (!tgzBtn) return;

    const rid = (
      row.getAttribute("data-rid") ||
      row.getAttribute("data-run-id") ||
      row.getAttribute("data-runid") ||
      extractRidFromText(txt(row))
    ).trim();

    if (!rid) return;

    // action container: try parent of TGZ
    const actionBox = tgzBtn.parentElement || row;
    if (hasAuditBtn(actionBox)) return;

    const b = document.createElement("button");
    b.textContent = "Audit Pack";
    b.className = tgzBtn.className || "btn";
    b.style.marginLeft = "8px";
    b.title = "Download audit evidence pack";
    b.addEventListener("click", (ev)=>{
      ev.preventDefault();
      ev.stopPropagation();
      const url = "/api/vsp/audit_pack?rid=" + encodeURIComponent(rid);
      window.open(url, "_blank", "noopener");
    });

    actionBox.appendChild(b);
  }

  function scan(){
    // anchor: Copy RID button exists per row
    const copyBtns = qsa("button,a").filter(x => txt(x).toLowerCase() === "copy rid");
    for (const cb of copyBtns){
      const row = findRowContainerFromCopyBtn(cb);
      if (row) ensureAuditOnRow(row);
    }
  }

  // run now and retry (async render/pagination)
  let tries = 0;
  const t = setInterval(()=> {
    tries++;
    try { scan(); } catch(e){}
    if (tries >= 20) clearInterval(t);
  }, 500);

  // mutation observer for dynamic rerender
  try {
    const mo = new MutationObserver(()=> { try { scan(); } catch(e){} });
    mo.observe(document.documentElement, { childList:true, subtree:true });
  } catch(e){}
})();
 /* ===================== /VSP_P1_RUNS_AUDIT_PACK_BTN_V2 ===================== */
""")

p.write_text(s.rstrip() + "\n\n" + inject + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] audit pack per-row v2 installed."
