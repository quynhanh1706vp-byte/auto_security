#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_bundle_tabs5_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_p3k13d_${TS}"
echo "[BACKUP] ${F}.bak_p3k13d_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P3K13D_KILL_P2BADGES_TIMEOUT_LOGS_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) Remove any console.* statement that mentions the noisy phrases
patterns = [
    r'console\.(?:log|info|warn|error|debug)\([^;]*?\[P2Badges\][^;]*?rid_latest[^;]*?timeout[^;]*?\);\s*',
    r'console\.(?:log|info|warn|error|debug)\([^;]*?rid_latest fetch fail timeout[^;]*?\);\s*',
    r'console\.(?:log|info|warn|error|debug)\([^;]*?Dashboard error:\s*timeout[^;]*?\);\s*',
]
before = s
for pat in patterns:
    s = re.sub(pat, '/*silenced:'+marker+'*/\n', s, flags=re.S)

removed = (before != s)

# 2) Add a universal console filter (log/info/warn/error) for these exact noisy messages
shim = r"""/* === VSP_P3K13D_KILL_P2BADGES_TIMEOUT_LOGS_V1 === */
(function(){
  try{
    function _join(args){
      try{ return Array.prototype.slice.call(args).map(x=>String(x)).join(" "); }catch(e){ return ""; }
    }
    function wrap(m){
      const _orig = console[m];
      if (typeof _orig !== "function") return;
      console[m] = function(){
        try{
          const msg = _join(arguments);
          if (msg.includes("[P2Badges]") && msg.includes("rid_latest") && msg.includes("timeout")) return;
          if (msg.includes("rid_latest fetch fail timeout")) return;
          if (msg.includes("Dashboard error: timeout")) return;
        }catch(e){}
        return _orig.apply(console, arguments);
      };
    }
    ["log","info","warn","error","debug"].forEach(wrap);
  }catch(e){}
})();
"""

# insert shim at top (after shebang if any)
ins_at = 0
if s.startswith("#!"):
    nl = s.find("\n")
    ins_at = nl+1 if nl >= 0 else 0

s = s[:ins_at] + shim + "\n" + s[ins_at:]
p.write_text(s, encoding="utf-8")
print("[OK] patched:", str(p), "removed_console_stmt=", removed)
PY

echo "== node -c =="
node -c "$F" >/dev/null
echo "[OK] node -c passed"

echo "== restart =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }

echo "== smoke marker =="
grep -n "VSP_P3K13D_KILL_P2BADGES_TIMEOUT_LOGS_V1" "$F" | head -n 3 || true
echo "[DONE] p3k13d_tabs5_kill_p2badges_timeout_logs_v1"
