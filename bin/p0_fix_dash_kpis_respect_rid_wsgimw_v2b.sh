#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need head
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID1="${1:-VSP_CI_20251215_173713}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_dashkpis_rid_${TS}"
ok "backup: ${WSGI}.bak_dashkpis_rid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P0_DASH_KPIS_RESPECT_RID_WSGIMW_V2B"
if MARK in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

lines = s.splitlines(True)

def patch_block(i, kind):
    """
    i points to line containing: if path == "/api/vsp/dash_kpis":  (or dash_charts)
    Insert rid_req snippet right after the if line (once),
    then patch the first 'rid = ...' assignment within next ~120 lines to use _rid_req.
    """
    if_line = lines[i]
    indent = re.match(r"^(\s*)", if_line).group(1)
    inner = indent + "    "

    # Insert snippet if not already present nearby
    snippet_tag = f"{inner}# {MARK} ({kind})\n"
    if i+1 < len(lines) and MARK in lines[i+1]:
        pass
    else:
        snippet = (
            snippet_tag +
            f"{inner}try:\n"
            f"{inner}    import urllib.parse as _vsp_urlparse\n"
            f"{inner}    _qs = _vsp_urlparse.parse_qs(environ.get('QUERY_STRING',''))\n"
            f"{inner}    _rid_req = (_qs.get('rid',[''])[0] or '').strip()\n"
            f"{inner}except Exception:\n"
            f"{inner}    _rid_req = ''\n"
        )
        lines.insert(i+1, snippet)

    # Find first rid assignment after this point
    patched_assign = False
    start = i+1
    end = min(len(lines), i+140)
    for j in range(start, end):
        # stop if we leave this if-block (heuristic: line with same indent 'if path ==' for other path)
        if j > start and re.match(rf"^{re.escape(indent)}if\s+path\s*==\s*['\"]\/api\/vsp\/", lines[j]):
            break

        m = re.match(rf"^{re.escape(inner)}rid\s*=\s*(.+?)\s*$", lines[j].rstrip("\n"))
        if m and "_rid_req" not in lines[j]:
            expr = m.group(1)
            # wrap original expression; rid_req wins
            lines[j] = f"{inner}rid = (_rid_req or ({expr}))\n"
            patched_assign = True
            break

    return patched_assign

# Patch all dash_kpis + dash_charts blocks
pat_kpis = re.compile(r'^\s*if\s+path\s*==\s*["\']/api/vsp/dash_kpis["\']\s*:\s*$')
pat_charts = re.compile(r'^\s*if\s+path\s*==\s*["\']/api/vsp/dash_charts["\']\s*:\s*$')

kpis_hits = 0
charts_hits = 0
kpis_patched = 0
charts_patched = 0

i = 0
while i < len(lines):
    ln = lines[i].rstrip("\n")
    if pat_kpis.match(ln):
        kpis_hits += 1
        if patch_block(i, "dash_kpis"):
            kpis_patched += 1
        i += 1
        continue
    if pat_charts.match(ln):
        charts_hits += 1
        if patch_block(i, "dash_charts"):
            charts_patched += 1
        i += 1
        continue
    i += 1

out = "".join(lines)
out += f"\n# {MARK} hits_kpis={kpis_hits} patched_kpis={kpis_patched} hits_charts={charts_hits} patched_charts={charts_patched}\n"
p.write_text(out, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print(f"[OK] patched. kpis_hits={kpis_hits} kpis_patched={kpis_patched} charts_hits={charts_hits} charts_patched={charts_patched}")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.6
fi

echo "== [VERIFY] dash_kpis should differ across rid (if runs differ) =="
RID2="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(((j.get("runs") or [{}])[0]).get("rid",""))')"
echo "RID1=$RID1"
echo "RID2=$RID2"
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("RID1 total", j.get("total_findings"), "ct", j.get("counts_total"))'
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID2" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("RID2 total", j.get("total_findings"), "ct", j.get("counts_total"))'

echo "== [VERIFY] run_gate_summary counts_total (ground truth per rid) =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID1&path=run_gate_summary.json" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("RID1 counts_total", j.get("counts_total"))'
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID2&path=run_gate_summary.json" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("RID2 counts_total", j.get("counts_total"))'

ok "DONE"
