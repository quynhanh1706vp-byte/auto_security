#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_trendfix_${TS}"
echo "[BACKUP] ${APP}.bak_trendfix_${TS}"

python3 - "$APP" <<'PY'
from pathlib import Path
import re, sys, textwrap

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_TREND_V1_ALLOW_AND_ROBUST_V1"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

# locate decorator containing /api/vsp/trend_v1
m = re.search(r'(?m)^[ \t]*@app\.(?:get|route)\(\s*[\'"]/api/vsp/trend_v1[\'"]', s)
if not m:
    print("[ERR] cannot find route decorator for /api/vsp/trend_v1 in vsp_demo_app.py")
    raise SystemExit(2)

# find the following def line
defm = re.search(r'(?m)^[ \t]*def[ \t]+[A-Za-z0-9_]+\s*\(', s[m.end():])
if not defm:
    print("[ERR] cannot find def after trend_v1 decorator")
    raise SystemExit(2)

def_start = m.start() + defm.start() + (s[m.start():].splitlines()[0].__len__() * 0)  # no-op, keep simple
# Actually use indices from the original string:
decor_start = m.start()
# def line absolute:
def_abs = m.end() + defm.start()
# find indentation of def line
line_start = s.rfind("\n", 0, def_abs) + 1
indent = re.match(r'[ \t]*', s[line_start:def_abs]).group(0)

# find end of function block by scanning forward until next top-level decorator/def/class with <= indent
i = def_abs
# advance to next line after def
i = s.find("\n", i)
if i == -1: i = len(s)
i += 1
end = len(s)
pat = re.compile(r'(?m)^(?P<ind>[ \t]*)(@app\.|def\s+|class\s+)')
for mm in pat.finditer(s, i):
    ind = mm.group("ind")
    # if indentation is <= function indent, we treat as end
    if len(ind.replace("\t","    ")) <= len(indent.replace("\t","    ")):
        end = mm.start()
        break

new_block = textwrap.dedent(f"""
@app.get("/api/vsp/trend_v1")
def api_vsp_trend_v1():
    \"\"\"{MARK}
    Robust trend endpoint: never 'not allowed'. Returns points with keys: label, run_id, total, ts.
    Uses run_gate_summary.json if available; falls back to findings_unified.json length.
    \"\"\"
    import os, json, datetime
    from flask import request, jsonify

    rid = (request.args.get("rid") or "").strip()
    limit = int(request.args.get("limit") or 20)
    if limit < 5: limit = 5
    if limit > 80: limit = 80

    # candidate roots (keep conservative + cheap)
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci/VSP_CI",
    ]
    # normalize: only existing dirs
    roots = [r for r in roots if os.path.isdir(r)]

    def list_run_dirs():
        dirs = []
        for r in roots:
            try:
                for name in os.listdir(r):
                    if not (name.startswith("VSP_") or name.startswith("RUN_")):
                        continue
                    full = os.path.join(r, name)
                    if os.path.isdir(full):
                        try:
                            mt = os.path.getmtime(full)
                        except Exception:
                            mt = 0
                        dirs.append((mt, name, full))
            except Exception:
                pass
        dirs.sort(key=lambda x: x[0], reverse=True)
        return dirs

    def load_json(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None

    def get_total_from_gate(j):
        if not isinstance(j, dict): return None
        for k in ("total", "total_findings", "findings_total", "total_unified"):
            v = j.get(k)
            if isinstance(v, int): return v
        c = j.get("counts") or j.get("severity_counts") or j.get("by_severity")
        if isinstance(c, dict):
            sm = 0
            for vv in c.values():
                if isinstance(vv, int): sm += vv
            return sm
        return None

    points = []
    for mt, name, d in list_run_dirs()[: max(limit*3, limit) ]:
        # if rid specified, prefer keeping it in the window but still build a series
        gate = load_json(os.path.join(d, "run_gate_summary.json")) or load_json(os.path.join(d, "reports", "run_gate_summary.json"))
        total = get_total_from_gate(gate)
        if total is None:
            fu = load_json(os.path.join(d, "findings_unified.json")) or load_json(os.path.join(d, "reports", "findings_unified.json"))
            if isinstance(fu, list):
                total = len(fu)
            elif isinstance(fu, dict) and isinstance(fu.get("findings"), list):
                total = len(fu.get("findings"))
        if total is None:
            continue

        ts = datetime.datetime.fromtimestamp(mt).isoformat(timespec="seconds")
        label = datetime.datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M")
        points.append({{"label": label, "run_id": name, "total": int(total), "ts": ts}})
        if len(points) >= limit:
            break

    # If rid exists but not in recent list, still return ok with empty or recent points
    return jsonify({{"ok": True, "rid_requested": rid, "limit": limit, "points": points}})
""").lstrip("\n")

# Replace the entire existing trend_v1 route block (decorator..function) with our new block
out = s[:decor_start] + new_block + "\n\n" + s[end:]
p.write_text(out, encoding="utf-8")
print("[OK] patched trend_v1 block in", p)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

# Try restart service if available, otherwise just remind command
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service | grep -q "$SVC"; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || systemctl restart "$SVC" || true
else
  echo "[INFO] systemd service not detected; restart your UI process manually if needed."
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[SMOKE] RID=$RID"
echo "[SMOKE] trend_v1:"
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=5" | head -c 260; echo
