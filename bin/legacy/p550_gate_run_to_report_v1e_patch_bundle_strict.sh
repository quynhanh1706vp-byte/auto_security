#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p550_gate_run_to_report_v1d.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p550e_${TS}"
echo "[OK] backup => ${F}.bak_p550e_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p550_gate_run_to_report_v1d.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the bundle success block near the end:
#   if ! download_first_working ...; then warn ...; else ok ...
# with strict gzip+size check.
pat = re.compile(r"""(?ms)
if\s+!\s*download_first_working\s+"BUNDLE"\s+"\$bundle_out"\s+"\$\{bundle_urls\[@\]\}";\s*then
\s*warn\s+"support bundle endpoint not found yet \(TODO\)\.\s*see \$OUT/tried_BUNDLE\.txt"
else
\s*ok\s+"support bundle downloaded"
fi
""")

repl = r'''
if ! download_first_working "BUNDLE" "$bundle_out" "${bundle_urls[@]}"; then
  warn "support bundle endpoint not found yet (TODO). see $OUT/tried_BUNDLE.txt"
else
  # STRICT: must look like gzip tarball (>= 1KB and gzip magic 1f8b)
  bsz="$(wc -c <"$bundle_out" | awk '{print $1}')"
  magic="$(python3 - <<'PY2' "$bundle_out"
import sys,binascii
b=open(sys.argv[1],'rb').read(2)
print(binascii.hexlify(b).decode())
PY2
)"
  if [ "$bsz" -lt 1024 ] || [ "$magic" != "1f8b" ]; then
    warn "support bundle looks invalid (size=${bsz} magic=${magic}). Treat as NOT READY for commercial bundle."
  else
    ok "support bundle downloaded (size=${bsz})"
  fi
fi
'''

s2, n = pat.subn(repl, s, count=1)
if n != 1:
    raise SystemExit("[ERR] could not patch bundle block (pattern not found)")
p.write_text(s2, encoding="utf-8")
print("[OK] patched bundle strict check")
PY

bash -n "$F" && echo "[OK] bash -n"
