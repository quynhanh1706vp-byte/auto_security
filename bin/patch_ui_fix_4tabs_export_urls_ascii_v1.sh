#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_export_ascii_${TS}"
echo "[BACKUP] $F.bak_fix_export_ascii_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

# normalize any weird escaped \" in the export candidates area
def norm_line(s: str) -> str:
    # aggressively remove \" -> " (only affects already-broken patches)
    return s.replace('\\"', '"')

lines = t.splitlines(True)
out = []
patched = 0

for ln in lines:
    if "/api/vsp/run_export_v3/" in ln and "fmt=${fmt}" in ln and "`" in ln:
        # force exact safe form (no unicode/escape)
        if "?fmt=${fmt}" in ln and "${String(__ciQ||\"\"" in ln:
            ln = norm_line(ln)
        if "String(__ciQ||" in ln and "replace(/^\\" in ln:
            ln = norm_line(ln)

    out.append(ln)

t2 = "".join(out)

# Force rewrite of the 5 canonical candidates if present (best-effort)
needles = [
    "/api/vsp/run_export_v3/${encodeURIComponent(selectedRid)}?fmt=${fmt}",
    "/api/vsp/run_export_v3/${encodeURIComponent(selectedRid)}?format=${fmt}",
    "/api/vsp/run_export_v3?rid=${encodeURIComponent(selectedRid)}&fmt=${fmt}",
    "/api/vsp/run_export_v3?run_id=${encodeURIComponent(selectedRid)}&fmt=${fmt}",
    "/api/vsp/run_export_v3?rid=${encodeURIComponent(selectedRid)}&format=${fmt}",
]
good_suffix = '${String(__ciQ||"").replace(/^\\?/, "&")}'  # accept leading '?' OR not
repl = [
    f'    `/api/vsp/run_export_v3/${{encodeURIComponent(selectedRid)}}?fmt=${{fmt}}{good_suffix}`,',
    f'    `/api/vsp/run_export_v3/${{encodeURIComponent(selectedRid)}}?format=${{fmt}}{good_suffix}`,',
    f'    `/api/vsp/run_export_v3?rid=${{encodeURIComponent(selectedRid)}}&fmt=${{fmt}}{good_suffix}`,',
    f'    `/api/vsp/run_export_v3?run_id=${{encodeURIComponent(selectedRid)}}&fmt=${{fmt}}{good_suffix}`,',
    f'    `/api/vsp/run_export_v3?rid=${{encodeURIComponent(selectedRid)}}&format=${{fmt}}{good_suffix}`,',
]

for i,n in enumerate(needles):
    if n in t2:
        # replace the whole line containing needle
        parts = t2.splitlines()
        for idx, L in enumerate(parts):
            if n in L and L.strip().startswith("`/api/vsp/run_export_v3"):
                parts[idx] = repl[i]
                patched += 1
        t2 = "\n".join(parts) + ("\n" if t2.endswith("\n") else "")

p.write_text(t2, encoding="utf-8")
print(f"[OK] patched_export_candidate_lines={patched}")
PY

node --check "$F" >/dev/null
echo "[OK] node --check JS syntax OK"
echo "[DONE] Now restart + hard refresh Ctrl+Shift+R"
