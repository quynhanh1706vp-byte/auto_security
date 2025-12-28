#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_gate_fix_v2_${TS}"
echo "[BACKUP] ${JS}.bak_gate_fix_v2_${TS}"

python3 - "$JS" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_GATE_STORY_FIX_RUNFILE_ALLOW_PARAMS_V2"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

# 1) Normalize wrong path (reports/...) -> run_gate.json (backend will fallback to summary if needed)
s2, n1 = re.subn(r"reports/run_gate_summary\.json", "run_gate.json", s)
s2, n2 = re.subn(r"run_gate_summary\.json", "run_gate.json", s2)  # keep it simple: always ask run_gate.json

# 2) Normalize query param name run_id -> rid (common mismatch)
s2, n3 = re.subn(r"(\?|&)(run_id)=", r"\1rid=", s2)

# 3) Append a fetch-rewrite guard so missing rid/path won't 400 anymore (uses RID from DOM)
guard = r"""
/* VSP_P1_GATE_STORY_FIX_RUNFILE_ALLOW_PARAMS_V2 */
(()=> {
  if (window.__vsp_p1_gate_story_fix_runfile_allow_params_v2) return;
  window.__vsp_p1_gate_story_fix_runfile_allow_params_v2 = true;

  function getRidFromDom(){
    try{
      const txt = (document.body && document.body.textContent) ? document.body.textContent : "";
      const m = txt.match(/RID:\s*([A-Za-z0-9_.\-]+)/);
      return m ? m[1] : "";
    }catch(e){ return ""; }
  }

  const origFetch = window.fetch;
  window.fetch = function(input, init){
    try{
      if (typeof input === "string" && input.includes("/api/vsp/run_file_allow")){
        let url = input;

        // If rid missing, try to attach from DOM
        if (!/[?&]rid=/.test(url)){
          const rid = getRidFromDom();
          if (rid){
            url += (url.includes("?") ? "&" : "?") + "rid=" + encodeURIComponent(rid);
          }
        }
        // If path missing, force run_gate.json (backend will fallback to run_gate_summary.json)
        if (!/[?&]path=/.test(url)){
          url += (url.includes("?") ? "&" : "?") + "path=" + encodeURIComponent("run_gate.json");
        }

        input = url;
      }
    }catch(e){}
    return origFetch(input, init);
  };

  console.log("[GateStoryV1] V2 fix: force rid+path for run_file_allow, path=run_gate.json");
})();
"""
p.write_text(s2 + "\n" + guard + "\n/* "+marker+" */\n", encoding="utf-8")

print("[OK] patched:", p)
print("[OK] changes:", {"reports->run_gate": n1, "summary->run_gate": n2, "run_id->rid": n3})
PY

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Expect: Run overall != UNKNOWN, tool badges updated."
