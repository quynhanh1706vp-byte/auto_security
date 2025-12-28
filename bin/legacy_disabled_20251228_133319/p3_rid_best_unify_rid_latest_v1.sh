#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ridbest_${TS}"
echo "[BACKUP] ${APP}.bak_ridbest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P3_RID_BEST_UNIFY_RIDLATEST_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# ---- helpers block to inject (safe, standalone) ----
helpers = r'''
# === {MARK} ===
import os, json
from datetime import datetime

def _vsp_parse_rid_ts(rid: str):
    """
    Accepts: VSP_CI_YYYYmmdd_HHMMSS, RUN_YYYYmmdd_HHMMSS, etc.
    Returns datetime or None.
    """
    m = re.search(r'(\d{8})_(\d{6})', rid or "")
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _vsp_candidate_roots():
    # Prefer out_ci first (commercial CI outputs), then out/ (legacy)
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
                # Heuristic: only directory, ignore hidden
                if name.startswith("."):
                    continue
                full = os.path.join(root, name)
                if os.path.isdir(full):
                    rids.append((name, full))
        except Exception:
            pass
    # de-dup by rid keeping first path (pref out_ci order)
    seen = set()
    uniq = []
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
        # Some unify formats: {"ok":true,"total":N,"items":[...]}
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
    # Any of these paths count as "usable"
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
        # quick size gate
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
            # csv: size gate is usually enough (header-only is still small)
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
            mtime = None
            try:
                mtime = os.path.getmtime(d)
            except Exception:
                mtime = 0
            usable.append((ts, mtime, rid, d))
    if not usable:
        # fallback: just newest dir by mtime (still better than nothing)
        fallback = []
        for rid, d in rids:
            try:
                mtime = os.path.getmtime(d)
            except Exception:
                mtime = 0
            ts = _vsp_parse_rid_ts(rid)
            fallback.append((ts, mtime, rid, d))
        if not fallback:
            return None
        fallback.sort(key=lambda x: ((x[0] or datetime.fromtimestamp(0)), x[1]), reverse=True)
        return fallback[0][2]
    usable.sort(key=lambda x: ((x[0] or datetime.fromtimestamp(0)), x[1]), reverse=True)
    return usable[0][2]
# === END {MARK} ===
'''.replace("{MARK}", MARK)

# ---- inject helpers near imports (after first "import re" or after initial imports) ----
if "import re" in s:
    s = s.replace("import re", "import re\n" + helpers, 1)
else:
    # prepend at top safely
    s = helpers + "\n" + s

# ---- replace rid_latest endpoint to return rid_best ----
# Try to replace the whole rid_latest route function block.
pat = re.compile(
    r'(?s)@app\.(?:get|route)\(\s*[\'"]/api/vsp/rid_latest[\'"]\s*\).*?\n'
    r'(?:@app\..*?\n)*'
    r'\s*def\s+\w+\(.*?\):.*?'
    r'(?=\n@app\.|\nif\s+__name__\s*==|\Z)'
)

new_block = r'''
@app.get("/api/vsp/rid_best")
def api_vsp_rid_best():
    rid = _vsp_pick_rid_best()
    return {"ok": True, "rid": rid or ""}

@app.get("/api/vsp/rid_latest")
def api_vsp_rid_latest():
    # Commercial meaning: latest USABLE rid (has findings_unified.* non-empty)
    rid = _vsp_pick_rid_best()
    return {"ok": True, "rid": rid or "", "mode": "best_usable"}
'''.lstrip("\n")

m = pat.search(s)
if not m:
    # If not found, append routes at end (best effort).
    print("[WARN] could not locate existing /api/vsp/rid_latest route; appending new routes (may conflict if already defined).")
    s = s + "\n\n" + new_block
else:
    s = s[:m.start()] + new_block + s[m.end():]
    print("[OK] patched /api/vsp/rid_latest to best usable")

p.write_text(s, encoding="utf-8")
print("[OK] write:", p)
PY

# quick syntax check
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

# restart service if exists
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q "^${SVC}"; then
    echo "[INFO] restarting ${SVC}"
    sudo systemctl restart "${SVC}"
    sleep 0.5
    sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }
  else
    echo "[WARN] systemd unit not found: ${SVC} (skip restart)"
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

echo "[DONE] p3_rid_best_unify_rid_latest_v1"
