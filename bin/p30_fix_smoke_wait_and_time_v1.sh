#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p30_cache_findings_unified_v1_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_waittime_${TS}"
echo "[BACKUP] ${F}.bak_waittime_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("bin/p30_cache_findings_unified_v1_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

if "P30_WAIT_UI_READY_V1" not in s:
    s=s.replace('echo "== [SMOKE] cache header check (2 hits) =="',
                'echo "== [SMOKE] cache header check (2 hits) ==\"\n'
                'echo \"== [WAIT] UI ready (selfcheck_p0) ==\"\n'
                'for i in $(seq 1 50); do\n'
                '  if curl -fsS -o /dev/null --connect-timeout 1 --max-time 4 \"$BASE/api/vsp/selfcheck_p0\" >/dev/null 2>&1; then\n'
                '    echo \"[OK] UI ready\"; break\n'
                '  fi\n'
                '  sleep 0.2\n'
                'done\n'
                '# P30_WAIT_UI_READY_V1\n'
                )
# show time_total by printing it separately (avoid awk eating it)
s=s.replace('curl -sS -D- "$BASE/api/vsp/findings_unified_v1/$RID" -o /dev/null | awk',
            'curl -sS -D- -o /dev/null -w "time_total=%{time_total}\\n" "$BASE/api/vsp/findings_unified_v1/$RID" | awk')
p.write_text(s, encoding="utf-8")
print("[OK] patched wait+time display")
PY
