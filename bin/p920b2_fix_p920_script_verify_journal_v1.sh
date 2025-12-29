#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p920_p0plus_ops_evidence_logs_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p920b2_${TS}"
echo "[OK] backup => ${F}.bak_p920b2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("bin/p920_p0plus_ops_evidence_logs_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")

needle = 'j=json.load(open("out_ci/p920_"'
idx = s.find(needle)

# fallback needle if string got slightly changed
if idx < 0:
    needle2 = 'journal.json","r",encoding="utf-8")'
    idx = s.find(needle2)

if idx < 0:
    print("[WARN] cannot find broken journal verify line; nothing changed")
    raise SystemExit(0)

start = s.rfind("python3 - <<'PY'\n", 0, idx)
if start < 0:
    # maybe there is whitespace
    start = s.rfind("python3 - <<'PY'\r\n", 0, idx)
if start < 0:
    raise SystemExit("[ERR] cannot locate start of python heredoc for journal verify")

end = s.find("\nPY\n", idx)
if end < 0:
    raise SystemExit("[ERR] cannot locate end marker (\\nPY\\n) for journal verify heredoc")
end += len("\nPY\n")

replacement = (
    "python3 - \"$OUT\" <<'PY'\n"
    "import json, sys, pathlib\n"
    "out = pathlib.Path(sys.argv[1])\n"
    "j = json.load(open(out/\"journal.json\", \"r\", encoding=\"utf-8\"))\n"
    "print(\"journal ok=\", j.get(\"ok\"), \"svc=\", j.get(\"svc\"))\n"
    "PY\n"
)

s2 = s[:start] + replacement + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched journal verify heredoc safely")
PY

bash -n "$F"
echo "[OK] bash -n OK: $F"
