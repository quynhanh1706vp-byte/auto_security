#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need sudo; need date

python3 - <<'PY'
from pathlib import Path
import datetime, re

ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
marker="VSP_P431B_RL_GUARD_V1"
guard=r"""
;(()=>{ 
  // VSP_P431B_RL_GUARD_V1
  if (window.VSP_RL_fetch) return;
  const _fetch = (window.fetch ? window.fetch.bind(window) : null);
  const st = window.__VSP_RL_STATE__ = window.__VSP_RL_STATE__ || { last: 0, inflight: 0, min_ms: 15000 };
  function _fake(status, why){
    return { ok:false, status, json: async()=>({skipped:why}), text: async()=>("") };
  }
  window.VSP_RL_fetch = function(url, opts){
    try{
      if (!_fetch) return Promise.resolve(_fake(599,"no_fetch"));
      if (document && document.hidden) return Promise.resolve(_fake(204,"hidden"));
      const now = Date.now();
      if (st.inflight) return Promise.resolve(_fake(204,"inflight"));
      if (now - st.last < st.min_ms) return Promise.resolve(_fake(204,"throttled"));
      st.last = now; st.inflight = 1;
      return _fetch(url, Object.assign({cache:"no-store"}, (opts||{}))).finally(()=>{ st.inflight=0; });
    }catch(e){
      return Promise.resolve(_fake(598,"exception"));
    }
  };
})();
"""

targets=[
  Path("static/js/vsp_runs_quick_actions_v1.js"),
  Path("static/js/vsp_runs_reports_overlay_v1.js"),
  Path("static/js/vsp_ui_shell_v1.js"),
]
patched=0
for p in targets:
  if not p.exists(): 
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  if "release_latest" not in s:
    continue
  if marker in s:
    continue
  bak=p.with_suffix(p.suffix+f".bak_p431b_{ts}")
  bak.write_text(s, encoding="utf-8")
  s2=guard + "\n" + s
  s2=re.sub(r'fetch\(\s*([\'"])(\/?api\/vsp\/release_latest)\1', r'VSP_RL_fetch(\1\2\1', s2)
  p.write_text(s2, encoding="utf-8")
  patched += 1
  print("[OK] patched", p.name, "backup=", bak.name)
print("patched=", patched)
PY

sudo systemctl restart vsp-ui-8910.service
echo "[OK] restarted"
