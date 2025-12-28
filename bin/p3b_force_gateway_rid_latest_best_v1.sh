#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

targets=()
[ -f "wsgi_vsp_ui_gateway.py" ] && targets+=("wsgi_vsp_ui_gateway.py")
[ -f "vsp_demo_app.py" ] && targets+=("vsp_demo_app.py")

if [ "${#targets[@]}" -eq 0 ]; then
  echo "[ERR] missing both wsgi_vsp_ui_gateway.py and vsp_demo_app.py"
  exit 2
fi

echo "== [0] backup =="
for f in "${targets[@]}"; do
  cp -f "$f" "${f}.bak_ridbest_gateway_${TS}"
  echo "[BACKUP] ${f}.bak_ridbest_gateway_${TS}"
done

echo "== [1] patch files =="
python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P3B_FORCE_GATEWAY_RID_LATEST_BEST_V1"

HELPERS = r'''
# === __MARK__ ===
import os, json
import re
from datetime import datetime

def _vsp_parse_rid_ts(rid: str):
    m = re.search(r'(\d{8})_(\d{6})', rid or "")
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
            # CSV: require non-trivial size
            try:
                if os.path.getsize(fp) > 50:
                    return True
            except Exception:
                pass
    return False

def _vsp_pick_rid_best():
    rids = _vsp_list_rids()
    usable=[]
    for rid, d in rids:
        if _vsp_is_usable_rid_dir(d):
            ts=_vsp_parse_rid_ts(rid)
            try:
                mtime=os.path.getmtime(d)
            except Exception:
                mtime=0
            usable.append((ts, mtime, rid))
    if not usable:
        fb=[]
        for rid, d in rids:
            ts=_vsp_parse_rid_ts(rid)
            try:
                mtime=os.path.getmtime(d)
            except Exception:
                mtime=0
            fb.append((ts, mtime, rid))
        if not fb:
            return None
        fb.sort(key=lambda x: ((x[0] or datetime.fromtimestamp(0)), x[1]), reverse=True)
        return fb[0][2]
    usable.sort(key=lambda x: ((x[0] or datetime.fromtimestamp(0)), x[1]), reverse=True)
    return usable[0][2]
# === END __MARK__ ===
'''.replace("__MARK__", MARK).lstrip("\n")

ROUTES = r'''
@app.get("/api/vsp/rid_best")
def api_vsp_rid_best():
    rid = _vsp_pick_rid_best()
    return {"ok": True, "rid": rid or ""}

@app.get("/api/vsp/rid_latest")
def api_vsp_rid_latest():
    rid = _vsp_pick_rid_best()
    return {"ok": True, "rid": rid or "", "mode": "best_usable"}
'''.lstrip("\n")

def inject_helpers_after_imports(text: str) -> str:
    # remove old helper blocks
    text = re.sub(r'(?s)\n?# === '+re.escape(MARK)+r' ===.*?# === END '+re.escape(MARK)+r' ===\n?', "\n", text)

    lines = text.splitlines(True)
    i = 0
    while i < len(lines) and (lines[i].startswith("#!") or re.match(r'^\s*#.*$', lines[i]) or re.match(r'^\s*$', lines[i])):
        i += 1
    while i < len(lines) and re.match(r'^(import|from)\s+\S+', lines[i]):
        i += 1
    lines.insert(i, HELPERS + "\n")
    return "".join(lines)

def replace_rid_latest_block(text: str) -> str:
    # Replace any decorator line containing /api/vsp/rid_latest and its following def-block.
    lines = text.splitlines(True)
    out = []
    i = 0
    replaced = False

    def is_top_decorator(line: str) -> bool:
        return line.startswith("@")  # top-level decorator only

    while i < len(lines):
        line = lines[i]
        if is_top_decorator(line) and "/api/vsp/rid_latest" in line:
            # start of rid_latest decorator; skip decorators + def block
            start = i
            j = i
            # consume decorators
            while j < len(lines) and is_top_decorator(lines[j]):
                j += 1
            # must be def next
            if j < len(lines) and lines[j].startswith("def "):
                # consume until next top-level decorator or end or if __name__
                k = j + 1
                while k < len(lines):
                    if lines[k].startswith("@"):
                        break
                    if re.match(r'^if\s+__name__\s*==', lines[k]):
                        break
                    k += 1
                # drop old block, insert our routes (rid_best + rid_latest)
                out.append(ROUTES + "\n")
                i = k
                replaced = True
                continue
            # if not def, fall through (weird file), don't replace
        out.append(line)
        i += 1

    if not replaced:
        # append routes at end (best effort)
        out.append("\n\n" + ROUTES + "\n")
    return "".join(out), replaced

for fname in ["wsgi_vsp_ui_gateway.py","vsp_demo_app.py"]:
    p = Path(fname)
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    s = inject_helpers_after_imports(s)
    s, replaced = replace_rid_latest_block(s)

    p.write_text(s, encoding="utf-8")
    print(f"[OK] patched {fname} (rid_latest_replaced={replaced})")
PY

echo "== [2] compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py 2>/dev/null || true
python3 -m py_compile vsp_demo_app.py 2>/dev/null || true
echo "[OK] py_compile attempted"

echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q "^${SVC}"; then
    sudo systemctl restart "${SVC}"
    sleep 0.5
    sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 4; }
  else
    echo "[WARN] unit not found: ${SVC} (skip restart)"
  fi
else
  echo "[WARN] systemctl not found (skip restart)"
fi

echo "== [4] smoke rid_latest / rid_best =="
RID_L="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("rid",""))')"
RID_B="$(curl -fsS "$BASE/api/vsp/rid_best"   | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("rid",""))')"
echo "rid_latest=$RID_L"
echo "rid_best=$RID_B"
if [ -n "$RID_L" ] && [ -n "$RID_B" ] && [ "$RID_L" != "$RID_B" ]; then
  echo "[WARN] rid_latest != rid_best (still mismatched)"
fi

echo "== [5] smoke run_file_allow findings_unified.json =="
if [ -n "$RID_L" ]; then
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID_L&path=findings_unified.json&limit=5" \
    | python3 -c 'import sys,json; j=json.load(sys.stdin); print("from=",j.get("from"),"len=",len(j.get("findings") or []))'
else
  echo "[WARN] rid_latest empty; cannot smoke run_file_allow"
fi

echo "[DONE] p3b_force_gateway_rid_latest_best_v1"
