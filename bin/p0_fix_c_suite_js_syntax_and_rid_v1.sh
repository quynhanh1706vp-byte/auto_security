#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp; need grep
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node --check)"; exit 2; }
command -v systemctl >/dev/null 2>&1 || true

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_fixsyntax_rid_${TS}"
echo "[BACKUP] ${JS}.bak_fixsyntax_rid_${TS}"

echo "== [1] Show current syntax check =="
if node --check "$JS" >/dev/null 2>&1; then
  echo "[OK] node --check: clean (before patch)"
else
  echo "[WARN] node --check: has error (before patch)"
  node --check "$JS" 2>&1 | head -n 20 || true
fi

python3 - "$JS" <<'PY'
from pathlib import Path
import re

p = Path(__import__("sys").argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

# (A) Fix common fatal syntax: a line starting with "=" (often created by bad patch/concat)
fixed_eq = 0
for i, ln in enumerate(lines):
    if re.match(r'^\s*=\s*', ln):
        # remove the leading '=' but keep indent
        lines[i] = re.sub(r'^(\s*)=\s*', r'\1', ln)
        fixed_eq += 1

# (B) Use stable rule_overrides endpoint (v1 is 500 in your console)
before = "".join(lines)
after = before.replace("/api/vsp/rule_overrides_v1", "/api/vsp/rule_overrides")
repl_ro = 1 if after != before else 0

# (C) Harden RID extraction: rid/RID + localStorage fallback; if still empty, fetch rid_latest
# We patch only if we can find a qs/rid block. Keep it safe: inject helper once.
s2 = after
if "window.__VSP_RID_HELPER_V1" not in s2:
    inject = r"""
/* __VSP_RID_HELPER_V1 */
window.__VSP_RID_HELPER_V1 = (function(){
  function qsGet(){
    try { return new URLSearchParams(location.search); } catch(e){ return new URLSearchParams(""); }
  }
  async function pickRid(){
    const qs = qsGet();
    let rid = (qs.get("rid") || qs.get("RID") || localStorage.getItem("vsp_rid") || "").trim();
    if (rid) { try{ localStorage.setItem("vsp_rid", rid); }catch(e){} return rid; }
    // fallback: ask backend
    try{
      const r = await fetch("/api/vsp/rid_latest", {cache:"no-store"});
      const j = await r.json().catch(()=>null);
      rid = (j && (j.rid || j.RID) || "").toString().trim();
      if (rid) { try{ localStorage.setItem("vsp_rid", rid); }catch(e){} }
      return rid || "";
    }catch(e){ return ""; }
  }
  function withRid(url, rid){
    try{
      const u = new URL(url, location.origin);
      if (!u.searchParams.get("rid") && rid) u.searchParams.set("rid", rid);
      return u.toString();
    }catch(e){
      // plain string fallback
      if (rid && url.indexOf("rid=") < 0){
        return url + (url.indexOf("?")>=0 ? "&" : "?") + "rid=" + encodeURIComponent(rid);
      }
      return url;
    }
  }
  return { pickRid, withRid };
})();
"""
    # inject near top: after first "(function" or "(() =>" style IIFE header if possible
    m = re.search(r'\(function\s*\(\)\s*\{', s2)
    if m:
        ins_at = m.end()
        s2 = s2[:ins_at] + "\n" + inject + "\n" + s2[ins_at:]
    else:
        # fallback: prepend
        s2 = inject + "\n" + s2

# (D) Patch obvious export/run_file callers if present: ensure they pass rid
# Replace patterns like fetch("/api/vsp/export_csv?rid=" + rid) is ok.
# But if they call without rid or rid may be empty, wrap URL with helper.
def wrap_fetch_url(txt: str) -> str:
    # fetch("...") or fetch('...') literal endpoints we care
    patterns = [
        r'fetch\(\s*([\'\"])(/api/vsp/export_csv\?rid=)([^\1]*)\1',
        r'fetch\(\s*([\'\"])(/api/vsp/run_file\?rid=)([^\1]*)\1',
    ]
    out = txt
    # We won't do risky transforms here; helper exists and page code can call it if needed.
    return out

s3 = wrap_fetch_url(s2)

p.write_text(s3, encoding="utf-8")
print(f"[PATCH] fixed_leading_eq_lines={fixed_eq} replaced_rule_overrides_v1={repl_ro} injected_rid_helper={'__VSP_RID_HELPER_V1' in s3}")
PY

echo "== [2] Syntax check after patch =="
node --check "$JS"
echo "[OK] node --check: clean (after patch)"

echo "== [3] Restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  sudo systemctl --no-pager --full status "$SVC" | head -n 30 || true
else
  echo "[WARN] systemctl not found; restart manually if needed."
fi

echo "[DONE] Now hard refresh: Ctrl+F5 on /c/dashboard and /c/rule_overrides"
