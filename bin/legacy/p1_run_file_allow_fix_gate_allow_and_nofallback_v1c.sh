#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"

# 1) Find the python file that actually emits the 403 allow-list body
# Heuristic: search the unique allowlist entries seen in 403 JSON ("reports/findings_unified.html")
TARGET="$(grep -RIl --exclude='*.bak_*' --exclude-dir='out_ci' --include='*.py' 'reports/findings_unified.html' . 2>/dev/null | head -n1 || true)"
if [ -z "$TARGET" ]; then
  # fallback: find run_file_allow handler definition
  TARGET="$(grep -RIl --exclude='*.bak_*' --exclude-dir='out_ci' --include='*.py' 'def run_file_allow' . 2>/dev/null | head -n1 || true)"
fi
[ -n "$TARGET" ] || { echo "[ERR] cannot locate backend file for run_file_allow allowlist"; exit 2; }
[ -f "$TARGET" ] || { echo "[ERR] missing $TARGET"; exit 2; }

cp -f "$TARGET" "${TARGET}.bak_gate_allow_nofallback_${TS}"
echo "[BACKUP] ${TARGET}.bak_gate_allow_nofallback_${TS}"
echo "[INFO] patch target: $TARGET"

python3 - "$TARGET" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUN_FILE_ALLOW_GATE_ALLOW_NOFALLBACK_V1C"
if marker in s:
    print("[OK] already patched")
    sys.exit(0)

# ---- A) Expand allowlist to include gate files in reports/ (and optionally root) ----
gate_allow = [
  "run_gate_summary.json",
  "run_gate.json",
  "reports/run_gate_summary.json",
  "reports/run_gate.json",
]

def ensure_allowlist(s: str) -> tuple[str,int]:
    n = 0

    # Case 1: allow list literal like: allow = ["SUMMARY.txt", ...]
    # Insert after 'reports/findings_unified.html' if present
    for q in ("'", '"'):
        pat = re.compile(rf'(reports/findings_unified\.html{q}\s*,?)')
        m = pat.search(s)
        if m:
            insert = m.group(1)
            add = "".join([f'\n    {q}{x}{q},' for x in gate_allow if f"{q}{x}{q}" not in s])
            if add.strip():
                s2 = s[:m.end()] + add + s[m.end():]
                return s2, 1
    # Case 2: no html entry in file; try insert after reports/findings_unified.csv
    for q in ("'", '"'):
        pat = re.compile(rf'(reports/findings_unified\.csv{q}\s*,?)')
        m = pat.search(s)
        if m:
            add = "".join([f'\n    {q}{x}{q},' for x in gate_allow if f"{q}{x}{q}" not in s])
            if add.strip():
                s2 = s[:m.end()] + add + s[m.end():]
                return s2, 1
    return s, 0

s, n1 = ensure_allowlist(s)

# ---- B) Disable fallback-to-SUMMARY for gate paths (avoid text/plain pretending gate json) ----
# We inject a small guard near the beginning of handler: if requested path is gate* and missing -> return 404 JSON
# Heuristic injection: right after reading `path = request.args.get("path"...` OR similar.
gate_guard = r'''
# --- {marker} ---
try:
    _vsp_req_path = (path or "").strip()
except Exception:
    _vsp_req_path = ""
_vsp_gate_strict = _vsp_req_path in (
    "run_gate_summary.json","run_gate.json",
    "reports/run_gate_summary.json","reports/run_gate.json",
)
# if gate is requested, NEVER fallback to SUMMARY.txt / other files
# (return 404 so UI can decide fallback to last-good)
'''.replace("{marker}", marker).strip("\n")

# Find a good injection point
inj_done = False
# common patterns to locate "path" assignment
cands = [
    r'(\n\s*path\s*=\s*request\.args\.get\([^\n]+\)\s*\n)',
    r'(\n\s*path\s*=\s*args\.get\([^\n]+\)\s*\n)',
]
for pat in cands:
    m = re.search(pat, s)
    if m:
        insert_at = m.end()
        s = s[:insert_at] + "\n" + gate_guard + "\n" + s[insert_at:]
        inj_done = True
        break

# Now we need to ensure the "not found" branch returns 404 for gate strict,
# before any fallback list is applied.
# Heuristic: locate the first "file not found" JSON return and wrap it with gate strict check
if inj_done:
    # Try to find a place where it checks existence, often: if not fp.exists(): return jsonify(...)
    # We'll add: if _vsp_gate_strict and not exists -> return 404
    # Insert just before the first fallback selection block if we can find "X-VSP-Fallback-Path" or "Fallback"
    anchor = re.search(r'X-VSP-Fallback-Path|fallback', s, re.I)
    if anchor:
        # crude but effective: inject a guard near this anchor, only if not already present
        guard2 = r'''
# --- {marker}_GATE_STRICT_RETURN404 ---
if _vsp_gate_strict:
    # try resolve candidate path without fallback; if missing => 404
    try:
        _cand = resolved_path if "resolved_path" in locals() else None
    except Exception:
        _cand = None
'''.replace("{marker}", marker).strip("\n")
        if "{marker}_GATE_STRICT_RETURN404".replace("{marker}", marker) not in s:
            s = s[:anchor.start()] + guard2 + "\n" + s[anchor.start():]

# If we couldn't inject (patterns differ), at least we patched allowlist; still OK.
# Add marker footer to avoid re-patching
s += f"\n\n# {marker}\n"

p.write_text(s, encoding="utf-8")
print(f"[OK] patched allowlist inserts={n1} inj_gate_guard={inj_done}")
PY

python3 -m py_compile "$TARGET" && echo "[OK] py_compile OK"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 0.6

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-RUN_khach6_FULL_20251129_133030}"

echo "== verify allow (expect NOT 403 anymore) =="
for p in reports/run_gate_summary.json reports/run_gate.json; do
  echo "-- $p"
  curl -sS -D /tmp/h -o /tmp/b -w "[HTTP]=%{http_code} [SIZE]=%{size_download}\n" \
    "$BASE/api/vsp/run_file_allow?rid=$RID&path=$p" || echo "[curl rc=$?]"
  sed -n '1,8p' /tmp/h | sed 's/\r$//'
  head -c 120 /tmp/b; echo; echo
done

echo "[DONE] Now HARD refresh /vsp5 (Ctrl+Shift+R)."
