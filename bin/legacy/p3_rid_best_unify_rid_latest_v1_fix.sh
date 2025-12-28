#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

# 0) Restore from latest backup created by previous attempt (bak_ridbest_*)
bak="$(ls -1t ${APP}.bak_ridbest_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  echo "[ERR] cannot find backup: ${APP}.bak_ridbest_*"
  exit 2
fi
cp -f "$bak" "$APP"
echo "[RESTORE] $bak -> $APP"

# 1) Patch safely (inject helper block at TOP-LEVEL after initial imports)
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P3_RID_BEST_UNIFY_RIDLATEST_V1"

# Remove any previous partial injection if exists
s = re.sub(
    r'(?s)\n?# === '+re.escape(MARK)+r' ===.*?# === END '+re.escape(MARK)+r' ===\n?',
    "\n",
    s
)

helpers = f'''
# === {MARK} ===
import os, json
from datetime import datetime

def _vsp_parse_rid_ts(rid: str):
    m = re.search(r'(\\d{{8}})_(\\d{{6}})', rid or "")
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _vsp_candidate_roots():
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    return [r for r in roots if os.path.isdir(r)]

def _vsp_list_rids():
    rids = []
    for root in _vsp_candidate_roots():
        try:
            for name in os.listdir(root):
                if name.startswith("."):
                    continue
                full = os.path.join(root, name)
                if os.path.isdir(full):
                    rids.append((name, full))
        except Exception:
            pass
    seen=set(); uniq=[]
    for rid, full in rids:
        if rid in seen:
            continue
        seen.add(rid)
        uniq.append((rid, full))
    return uniq

def _vsp_is_findings_nonempty_json(fp: str) -> bool:
    try:
        with open(fp, "r", encoding="utf-8", errors="replace") as f:
            j = json.load(f)
        for k in ("findings", "items", "results"):
            v = j.get(k)
            if isinstance(v, list) and len(v) > 0:
                return True
        total = j.get("total")
        if isinstance(total, int) and total > 0:
            return True
    except Exception:
        return False
    return False

def _vsp_is_findings_nonempty_sarif(fp: str) -> bool:
    try:
        with open(fp, "r", encoding="utf-8", errors="replace") as f:
            j = json.load(f)
        runs = j.get("runs") or []
        if not runs:
            return False
        for r in runs:
            res = (r or {}).get("results") or []
            if isinstance(res, list) and len(res) > 0:
                return True
    except Exception:
        return False
    return False

def _vsp_is_usable_rid_dir(rid_dir: str) -> bool:
    candidates = [
        "findings_unified.json",
        "reports/findings_unified.json",
        "report/findings_unified.json",
        "findings_unified.sarif",
        "reports/findings_unified.sarif",
        "report/findings_unified.sarif",
        "findings_unified.csv",
        "reports/findings_unified.csv",
        "report/findings_unified.csv",
    ]
    for rel in candidates:
        fp = os.path.join(rid_dir, rel)
        if not os.path.isfile(fp):
            continue
        try:
            if os.path.getsize(fp) <= 5:
                continue
        except Exception:
            continue

        if fp.endswith(".json"):
            if _vsp_is_findings_nonempty_json(fp):
                return True
        elif fp.endswith(".sarif"):
            if _vsp_is_findings_nonempty_sarif(fp):
                return True
        else:
            try:
                if os.path.getsize(fp) > 50:
                    return True
            except Exception:
                pass
    return False

def _vsp_pick_rid_best():
    rids = _vsp_list_rids()
    usable = []
    for rid, d in rids:
        if _vsp_is_usable_rid_dir(d):
            ts = _vsp_parse_rid_ts(rid)
            try:
                mtime = os.path.getmtime(d)
            except Exception:
                mtime = 0
            usable.append((ts, mtime, rid))
    if not usable:
        # fallback newest by ts/mtime
        fallback=[]
        for rid, d in rids:
            ts=_vsp_parse_rid_ts(rid)
            try:
                mtime=os.path.getmtime(d)
            except Exception:
                mtime=0
            fallback.append((ts, mtime, rid))
        if not fallback:
            return None
        fallback.sort(key=lambda x: ((x[0] or datetime.fromtimestamp(0)), x[1]), reverse=True)
        return fallback[0][2]
    usable.sort(key=lambda x: ((x[0] or datetime.fromtimestamp(0)), x[1]), reverse=True)
    return usable[0][2]
# === END {MARK} ===
'''.lstrip("\n")

# Find insertion point: after the initial top-level import block
lines = s.splitlines(True)
insert_at = 0
i = 0

# Skip shebang/encoding/comments/blanks at start
while i < len(lines) and (lines[i].startswith("#!") or re.match(r'^\s*#.*$', lines[i]) or re.match(r'^\s*$', lines[i])):
    i += 1

# Consume consecutive TOP-LEVEL imports (must start at column 0)
while i < len(lines) and re.match(r'^(import|from)\s+\S+', lines[i]):
    i += 1
insert_at = i

# Inject helpers there
lines.insert(insert_at, helpers + "\n")

s2 = "".join(lines)

# Replace existing rid_latest route safely (decorator must be at column 0)
pat = re.compile(
    r'(?s)^@app\.(?:get|route)\(\s*[\'"]/api/vsp/rid_latest[\'"]\s*\).*?\n'
    r'(?:^@app\..*?\n)*'
    r'^def\s+\w+\(.*?\):.*?'
    r'(?=^@app\.|^if\s+__name__\s*==|\Z)',
    re.MULTILINE
)

new_block = r'''
@app.get("/api/vsp/rid_best")
def api_vsp_rid_best():
    rid = _vsp_pick_rid_best()
    return {"ok": True, "rid": rid or ""}

@app.get("/api/vsp/rid_latest")
def api_vsp_rid_latest():
    # Commercial meaning: latest USABLE rid (has non-empty findings_unified.*)
    rid = _vsp_pick_rid_best()
    return {"ok": True, "rid": rid or "", "mode": "best_usable"}
'''.lstrip("\n")

m = pat.search(s2)
if m:
    s2 = s2[:m.start()] + new_block + s2[m.end():]
    print("[OK] patched existing /api/vsp/rid_latest")
else:
    # If not found, append at end (best effort)
    s2 = s2 + "\n\n" + new_block
    print("[WARN] could not locate existing /api/vsp/rid_latest; appended new routes")

p.write_text(s2, encoding="utf-8")
print("[OK] wrote", p)
PY

# 2) Compile check (show context if fail)
if ! python3 -m py_compile "$APP" 2> /tmp/vsp_py_compile_err.$$; then
  echo "[ERR] py_compile failed:"
  cat /tmp/vsp_py_compile_err.$$ | head -n 50
  # try to print around the reported line if available
  ln="$(grep -oE 'line [0-9]+' /tmp/vsp_py_compile_err.$$ | head -n1 | awk '{print $2}' || true)"
  if [ -n "${ln:-}" ]; then
    echo "---- context around line $ln ----"
    nl -ba "$APP" | sed -n "$((ln-25)),$((ln+25))p" || true
  fi
  rm -f /tmp/vsp_py_compile_err.$$
  exit 3
fi
rm -f /tmp/vsp_py_compile_err.$$
echo "[OK] py_compile OK"

# 3) Restart service
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q "^${SVC}"; then
    echo "[INFO] restarting ${SVC}"
    sudo systemctl restart "${SVC}"
    sleep 0.5
    sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 4; }
  else
    echo "[WARN] unit not found: ${SVC} (skip restart)"
  fi
else
  echo "[WARN] systemctl not found (skip restart)"
fi

echo "== [SMOKE] rid_latest / rid_best =="
curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest:", j.get("rid"), "mode:", j.get("mode"))'
curl -fsS "$BASE/api/vsp/rid_best"   | python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid_best:", j.get("rid"))'

echo "== [SMOKE] run_file_allow findings_unified.json =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
if [ -n "$RID" ]; then
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=5" \
    | python3 -c 'import sys,json; j=json.load(sys.stdin); print("from=",j.get("from"),"len=",len(j.get("findings") or []))'
else
  echo "[WARN] rid_latest empty; cannot smoke run_file_allow"
fi

echo "[DONE] p3_rid_best_unify_rid_latest_v1_fix"
