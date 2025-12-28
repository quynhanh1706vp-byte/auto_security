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

cp -f "$F" "${F}.bak_p3k13c_${TS}"
echo "[BACKUP] ${F}.bak_p3k13c_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P3K13C_SILENCE_P2BADGES_WARN_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

shim = r"""/* === VSP_P3K13C_SILENCE_P2BADGES_WARN_V1 === */
(function(){
  try{
    const _w = console.warn;
    console.warn = function(){
      try{
        const a0 = arguments && arguments.length ? arguments[0] : "";
        const msg = String(a0 || "");
        if (msg.includes("[P2Badges]") && msg.includes("rid_latest") && msg.includes("timeout")) return;
      }catch(e){}
      return _w.apply(console, arguments);
    };
  }catch(e){}
})();
"""

# insert near top (after possible shebang/comments)
ins_at = 0
if s.startswith("#!"):
    nl = s.find("\n")
    ins_at = nl+1 if nl >= 0 else 0

s2 = s[:ins_at] + shim + "\n" + s[ins_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", str(p))
PY

echo "== node -c =="
node -c "$F" >/dev/null
echo "[OK] node -c passed"

echo "== restart =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }

echo "== smoke marker =="
grep -n "VSP_P3K13C_SILENCE_P2BADGES_WARN_V1" "$F" | head -n 3 || true
echo "[DONE] p3k13c_tabs5_hard_silence_p2badges_warn_v1"
