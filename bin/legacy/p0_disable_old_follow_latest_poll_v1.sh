#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

F="static/js/vsp_tabs3_common_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_disable_oldpoll_${TS}"
echo "[BACKUP] ${F}.bak_disable_oldpoll_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_tabs3_common_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_DISABLE_OLD_FOLLOW_LATEST_POLL_V1"
if marker in s:
    print("[INFO] already patched"); raise SystemExit(0)

# 1) Gate the old start lines: pollLatest(); setInterval(pollLatest, 15000);
pat_start = re.compile(r"\n(\s*)pollLatest\(\);\s*\n\1setInterval\(pollLatest,\s*15000\);\s*\n")
def repl_start(m):
    ind = m.group(1)
    return (
        "\n" + ind + f"/* {marker} */\n"
        + ind + "if (!window.__vsp_rid_latest_verified_autorefresh_v1) {\n"
        + ind + "  pollLatest();\n"
        + ind + "  setInterval(pollLatest, 15000);\n"
        + ind + "}\n"
    )

s2, n1 = pat_start.subn(repl_start, s, count=1)

# 2) Gate the old Alt+L handler line: if(window.__vsp_rid_state.followLatest) pollLatest();
pat_key = re.compile(r"if\s*\(\s*window\.__vsp_rid_state\.followLatest\s*\)\s*pollLatest\(\);\s*")
s3, n2 = pat_key.subn("if (!window.__vsp_rid_latest_verified_autorefresh_v1 && window.__vsp_rid_state.followLatest) pollLatest(); ", s2, count=1)

if n1 == 0 and n2 == 0:
    print("[WARN] patterns not found; file layout differs. No change written.")
    raise SystemExit(0)

p.write_text(s3, encoding="utf-8")
print(f"[OK] patched old pollLatest gating: start={n1} keydown={n2}")
PY

node --check "$F" >/dev/null
echo "[OK] node --check: $F"
echo "[DONE] Ctrl+F5 on /data_source /rule_overrides /settings."
