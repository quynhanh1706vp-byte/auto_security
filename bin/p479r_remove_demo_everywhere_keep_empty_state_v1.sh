#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F_SIDEBAR="static/js/vsp_c_sidebar_v1.js"
F_RUNS="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p479r_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F_SIDEBAR" ] || { echo "[ERR] missing $F_SIDEBAR" | tee -a "$OUT/log.txt"; exit 2; }
[ -f "$F_RUNS" ] || { echo "[ERR] missing $F_RUNS" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F_SIDEBAR" "$OUT/vsp_c_sidebar_v1.js.bak_${TS}"
cp -f "$F_RUNS"    "$OUT/vsp_c_runs_v1.js.bak_${TS}"
echo "[OK] backups => $OUT/" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path

def remove_block(text: str, marker: str):
    # remove block that starts at comment /* marker */ and ends at first "\n})();"
    key = f"/* {marker} */"
    i = text.find(key)
    if i < 0:
        return text, False
    # include preceding newlines for clean removal
    start = text.rfind("\n\n", 0, i)
    if start < 0:
        start = max(0, i-2)
    end = text.find("\n})();", i)
    if end < 0:
        # fallback: remove from marker to EOF
        return text[:start], True
    end = end + len("\n})();")
    return text[:start] + text[end:], True

# 1) Remove DEMO mode (P479) from sidebar module
p = Path("static/js/vsp_c_sidebar_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
s2, changed = remove_block(s, "VSP_P479_DEMO_MODE_DASHBOARD_DS_V1")
if changed:
    p.write_text(s2, encoding="utf-8")
    print("[OK] removed P479 demo block from vsp_c_sidebar_v1.js")
else:
    print("[OK] P479 demo block not found (already removed)")

# 2) Remove old P477 (had demo toggle/sample runs) and replace with empty-state only
p2 = Path("static/js/vsp_c_runs_v1.js")
r = p2.read_text(encoding="utf-8", errors="replace")
r2, changed2 = remove_block(r, "VSP_P477_RUNS_EMPTY_STATE_DEMO_V1")

# add clean empty-state only (no localStorage, no fetch monkeypatch)
MARK2 = "VSP_P477C_EMPTY_STATE_ONLY_V1"
if MARK2 not in r2:
    r2 += r"""

/* VSP_P477C_EMPTY_STATE_ONLY_V1 */
(function(){
  function ensureCss(){
    if(document.getElementById("vsp_p477c_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p477c_css";
    st.textContent=`
#vsp_runs_empty_v1{
  margin:14px 0;
  padding:16px 16px;
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
}
#vsp_runs_empty_v1 .t{font-weight:900;font-size:14px;letter-spacing:.2px}
#vsp_runs_empty_v1 .d{opacity:.8;margin-top:6px;line-height:1.5}
`;
    document.head.appendChild(st);
  }

  function insertEmptyCard(){
    ensureCss();
    if(document.getElementById("vsp_runs_empty_v1")) return;

    // only show if page looks empty (no RID-like strings)
    const txt = (document.body && document.body.innerText) ? document.body.innerText : "";
    const hasRid = /VSP_CI_|RUN_|VSP_/.test(txt);
    if(hasRid) return;

    const root = document.querySelector(".vsp_p473_frame") || document.getElementById("vsp_p473_wrap") || document.body;
    if(!root) return;

    const card=document.createElement("div");
    card.id="vsp_runs_empty_v1";
    const t=document.createElement("div");
    t.className="t";
    t.textContent="No runs found (yet)";
    const d=document.createElement("div");
    d.className="d";
    d.textContent="This environment has no run history loaded. When runs exist, they will appear here automatically.";
    card.appendChild(t);
    card.appendChild(d);

    const tb=document.getElementById("vsp_p474_titlebar");
    if(tb && tb.parentNode) tb.parentNode.insertBefore(card, tb.nextSibling);
    else root.insertBefore(card, root.firstChild);
  }

  function boot(){
    setTimeout(insertEmptyCard, 700);
    setTimeout(insertEmptyCard, 1400);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
    p2.write_text(r2, encoding="utf-8")
    print("[OK] wrote P477C empty-state-only into vsp_c_runs_v1.js (and removed old P477 if present)")
else:
    if changed2:
        p2.write_text(r2, encoding="utf-8")
        print("[OK] removed old P477 from vsp_c_runs_v1.js (P477C already present)")
    else:
        print("[OK] P477C already present; no change")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F_SIDEBAR" >/dev/null 2>&1 || { echo "[ERR] node check failed: $F_SIDEBAR" | tee -a "$OUT/log.txt"; exit 2; }
  node --check "$F_RUNS" >/dev/null 2>&1 || { echo "[ERR] node check failed: $F_RUNS" | tee -a "$OUT/log.txt"; exit 2; }
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P479r done. Close ALL /c/* tabs, reopen /c/dashboard and /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
echo "[NOTE] If you ever clicked DEMO before: clear browser localStorage key VSP_DEMO_RUNS (see instructions below)." | tee -a "$OUT/log.txt"
