#!/usr/bin/env bash
set -euo pipefail
APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_gitleaks_rglob_v2_${TS}"
echo "[BACKUP] $APP.bak_gitleaks_rglob_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Find helper body
m = re.search(r"(?s)def\s+_vsp_preempt_statusv2_postprocess_v1\s*\(\s*payload\s*\)\s*:\s*.*?^\s*return\s+payload\s*$",
              t, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot locate _vsp_preempt_statusv2_postprocess_v1(payload) helper")

block = t[m.start():m.end()]

# Replace ci picking + gitleaks read with rglob-based approach
# We'll patch inside helper by regex replacements.
# 1) Replace ci assignment section to prefer ci_run_dir always.
block2 = re.sub(
    r"ci\s*=\s*payload\.get\(\"ci_run_dir\"\)\s*or\s*payload\.get\(\"ci_dir\"\)\s*or\s*payload\.get\(\"ci\"\)\s*or\s*\"\"",
    "ci = payload.get(\"ci_run_dir\") or payload.get(\"ci_dir\") or payload.get(\"ci\") or payload.get(\"ci_run\") or payload.get(\"ci_path\") or \"\"",
    block
)

# 2) Replace gitleaks read snippet with robust rglob discovery
# If existing gsum line exists, replace it; else append right before gate read.
if "gsum =" in block2:
    block2 = re.sub(
        r"gsum\s*=.*?\n\s*if\s+isinstance\(gsum,\s*dict\):",
        "        # robust autodiscovery for gitleaks summary (works even if layout changes)\n"
        "        gsum = None\n"
        "        try:\n"
        "            base = _P(ci)\n"
        "            # prefer the canonical path first\n"
        "            gsum = _readj(base / 'gitleaks' / 'gitleaks_summary.json') or _readj(base / 'gitleaks_summary.json')\n"
        "            if not isinstance(gsum, dict):\n"
        "                for fp in base.rglob('gitleaks_summary.json'):\n"
        "                    gsum = _readj(fp)\n"
        "                    if isinstance(gsum, dict):\n"
        "                        break\n"
        "        except Exception:\n"
        "            gsum = None\n"
        "        if isinstance(gsum, dict):",
        block2,
        flags=re.S
    )
else:
    # append before gate read
    block2 = block2.replace(
        "# if run_gate exists, take overall from it (single source of truth)",
        "        # robust autodiscovery for gitleaks summary (works even if layout changes)\n"
        "        gsum = None\n"
        "        try:\n"
        "            base = _P(ci)\n"
        "            gsum = _readj(base / 'gitleaks' / 'gitleaks_summary.json') or _readj(base / 'gitleaks_summary.json')\n"
        "            if not isinstance(gsum, dict):\n"
        "                for fp in base.rglob('gitleaks_summary.json'):\n"
        "                    gsum = _readj(fp)\n"
        "                    if isinstance(gsum, dict):\n"
        "                        break\n"
        "        except Exception:\n"
        "            gsum = None\n"
        "        if isinstance(gsum, dict):\n"
        "            payload['has_gitleaks'] = True\n"
        "            payload['gitleaks_verdict'] = str(gsum.get('verdict') or '')\n"
        "            try:\n"
        "                payload['gitleaks_total'] = int(gsum.get('total') or 0)\n"
        "            except Exception:\n"
        "                payload['gitleaks_total'] = 0\n"
        "            cc = gsum.get('counts')\n"
        "            payload['gitleaks_counts'] = cc if isinstance(cc, dict) else {}\n\n"
        "# if run_gate exists, take overall from it (single source of truth)"
    )

# Write back
t2 = t[:m.start()] + block2 + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] patched helper: ci pick + gitleaks rglob autodiscovery")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"
echo "DONE"
