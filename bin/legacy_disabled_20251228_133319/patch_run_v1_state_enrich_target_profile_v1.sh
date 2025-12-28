#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_enrich_${TS}"
echo "[BACKUP] $F.bak_enrich_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_V1_STATE_ENRICH_TARGET_PROFILE_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Heuristic: insert right before writing state json (json.dump/state json.dumps write_text)
patterns = [
    r"\n(\s*)(json\.dump\(\s*state\s*,\s*[^)]*\)\s*)",
    r"\n(\s*)([^#\n]*write_text\(\s*json\.dumps\(\s*state\s*[,)]\s*[^)]*\)\s*\)\s*)",
    r"\n(\s*)([^#\n]*json\.dumps\(\s*state\s*[,)]\s*[^)]*\)\s*)",
]

insertion = r"""
\1# === {MARK} ===
\1try:
\1    _req = request.get_json(silent=True) or {{}}
\1except Exception:
\1    _req = {{}}
\1# backfill target/profile/mode/target_type into state (avoid empty contract fields)
\1for _k in ("target","profile","mode","target_type"):
\1    if (not state.get(_k)) and (_req.get(_k) is not None):
\1        state[_k] = _req.get(_k) or ""
\1# keep minimal payload for later heuristics/debug
\1if "req_payload" not in state or not isinstance(state.get("req_payload"), dict):
\1    state["req_payload"] = {{}}
\1for _k in ("mode","profile","target_type","target"):
\1    if _k in _req:
\1        state["req_payload"][_k] = _req.get(_k)
\1# === END {MARK} ===
""".replace("{MARK}", MARK)

new = txt
applied = False
for pat in patterns:
    m = re.search(pat, new, flags=re.M)
    if m:
        new = re.sub(pat, lambda mm: insertion + "\n" + mm.group(0).lstrip("\n"), new, count=1, flags=re.M)
        applied = True
        break

if not applied:
    # fallback: try find "state = {" then insert after it (best effort)
    m = re.search(r"(\n\s*state\s*=\s*\{[\s\S]{0,800}?\}\s*)\n", new, flags=re.M)
    if m:
        block = m.group(1)
        new_block = block + insertion.replace("\\1", re.search(r"\n(\s*)state\s*=", block).group(1))
        new = new.replace(block, new_block, 1)
        applied = True

if not applied:
    print("[ERR] could not find insertion point; file layout unexpected.")
    raise SystemExit(2)

p.write_text(new, encoding="utf-8")
print("[OK] inserted", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
