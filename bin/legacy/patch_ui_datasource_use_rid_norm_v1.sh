#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_ridnorm_${TS}"
echo "[BACKUP] $F.bak_ridnorm_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_datasource_tab_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="// === VSP_P2_RID_NORM_V1 ==="
if TAG not in t:
    inject = r'''
// === VSP_P2_RID_NORM_V1 ===
function vspRidNorm(rid){
  rid = String(rid||"").trim();
  if (!rid) return rid;
  if (rid.startsWith("RUN_")) return rid.slice(4);
  return rid;
}
'''
    # put near top (after "use strict" if any)
    lines=t.splitlines(True)
    out=[]
    done=False
    for ln in lines:
      out.append(ln)
      if (not done) and ("use strict" in ln or ln.startswith("(function") or ln.startswith("//")):
        # insert once early (safe)
        if len(out) > 10:
          out.append(inject+"\n")
          done=True
    if not done:
      t = inject + "\n" + t
    else:
      t="".join(out)

# best-effort: in fetchFindings() ensure it uses rid_norm for PATH endpoint
# Replace occurrences of /findings_preview_v1/${encodeURIComponent(rid)} with rid_norm
t2=t.replace("encodeURIComponent(rid)", "encodeURIComponent(vspRidNorm(rid))")

p.write_text(t2, encoding="utf-8")
print("[OK] patched datasource to use rid_norm (RUN_ -> strip) for findings_preview PATH")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK"
echo "[DONE] restart + hard refresh Ctrl+Shift+R"
