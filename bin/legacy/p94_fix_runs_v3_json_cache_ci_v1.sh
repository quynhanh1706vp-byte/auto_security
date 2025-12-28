#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p94_runsv3_${TS}"
echo "[BACKUP] ${APP}.bak_p94_runsv3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P94_RUNS_V3_JSON_CACHE_CI_V1"

if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Ensure imports
def ensure_import(line_pat, insert):
    global s
    if re.search(line_pat, s, re.M):
        return
    # insert after flask import line if possible, else top
    m=re.search(r'(?m)^(from\s+flask\s+import\s+.+)$', s)
    if m:
        s = s[:m.end()] + "\n" + insert + s[m.end():]
    else:
        s = insert + "\n" + s

ensure_import(r'(?m)\bimport\s+json\b', "import json")
# Ensure Response/request/jsonify exist
if not re.search(r'(?m)^from\s+flask\s+import\s+.*\bResponse\b', s):
    # patch flask import line to include Response/request/jsonify safely
    s = re.sub(r'(?m)^from\s+flask\s+import\s+(.+)$',
               lambda m: m.group(0) if all(x in m.group(1) for x in ["Response","request","jsonify"]) else
                         "from flask import " + ", ".join(sorted(set([x.strip() for x in m.group(1).split(",")] + ["Response","request","jsonify"]))),
               s, count=1)

# Add helper + route at END so it wins
addon = r'''
# VSP_P94_RUNS_V3_JSON_CACHE_CI_V1
try:
    _VSP_P94_CACHE = {"t": 0.0, "key": "", "val": None}
except Exception:
    _VSP_P94_CACHE = None

def _vsp_p94_json(obj, code=200):
    try:
        return Response(json.dumps(obj, ensure_ascii=False), status=code, mimetype="application/json")
    except Exception as e:
        return Response('{"ok":false,"err":"json_encode_failed"}', status=500, mimetype="application/json")

def _vsp_p94_list_runs_dirs(include_ci: bool, limit: int):
    # Merge sources: out + (optionally) out_ci + ui/out_ci
    roots = ["/home/test/Data/SECURITY_BUNDLE/out"]
    if include_ci:
        roots += ["/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]
    items = []
    import os, time
    seen=set()
    for root in roots:
        try:
            if not os.path.isdir(root): 
                continue
            for name in os.listdir(root):
                if not (name.startswith("RUN_") or name.startswith("VSP_CI_")):
                    continue
                full=os.path.join(root, name)
                if not os.path.isdir(full):
                    continue
                if full in seen:
                    continue
                seen.add(full)
                try:
                    st=os.stat(full)
                    mtime=st.st_mtime
                except Exception:
                    mtime=time.time()
                items.append({
                    "rid": name,
                    "run_id": name,   # alias for UI compatibility
                    "name": name,
                    "path": full,
                    "root": root,
                    "ts": mtime,
                    "kind": ("ci" if name.startswith("VSP_CI_") else "run"),
                })
        except Exception:
            continue
    items.sort(key=lambda x: x.get("ts", 0), reverse=True)
    return items[:max(1, min(int(limit), 500))]

@app.get("/api/ui/runs_v3")
def vsp_p94_api_ui_runs_v3():
    # Always returns JSON (never HTML), supports include_ci=1
    try:
        include_ci = request.args.get("include_ci", "1") in ("1","true","yes","on")
        limit = int(request.args.get("limit", "200"))
        key = f"ci={1 if include_ci else 0}&limit={limit}"

        import time
        if _VSP_P94_CACHE and _VSP_P94_CACHE.get("val") is not None:
            if (time.time() - float(_VSP_P94_CACHE.get("t", 0.0))) < 15.0 and _VSP_P94_CACHE.get("key")==key:
                return _vsp_p94_json(_VSP_P94_CACHE["val"], 200)

        items = _vsp_p94_list_runs_dirs(include_ci=include_ci, limit=limit)
        out = {
            "ok": True,
            "ver": "p94",
            "include_ci": include_ci,
            "total": len(items),
            "items": items,
            "runs": items,   # legacy alias
        }
        if _VSP_P94_CACHE is not None:
            _VSP_P94_CACHE["t"] = time.time()
            _VSP_P94_CACHE["key"] = key
            _VSP_P94_CACHE["val"] = out
        return _vsp_p94_json(out, 200)
    except Exception as e:
        return _vsp_p94_json({"ok": False, "ver":"p94", "err": str(e)}, 500)
'''
s = s.rstrip() + "\n\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended P94 /api/ui/runs_v3 (JSON+cache+include_ci)")
PY

echo "== [P94] py_compile =="
python3 -m py_compile "$APP"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  echo "== [P94] restart service =="
  sudo systemctl restart "$SVC"
  sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; mkdir -p "$OUT"
EVID="$OUT/p94_runsv3_${TS}"
mkdir -p "$EVID"

echo "== [P94] smoke: capture runs_v3 raw (no pipe break) =="
curl -fsS -D "$EVID/hdr.txt" "$BASE/api/ui/runs_v3?limit=30&include_ci=1" -o "$EVID/body.json" || true
head -n 30 "$EVID/hdr.txt" || true
python3 - <<PY
import json, pathlib
b=pathlib.Path("$EVID/body.json").read_text(encoding="utf-8", errors="replace").strip()
print("body_len=", len(b))
print("body_head=", b[:120].replace("\n","\\n"))
try:
    j=json.loads(b)
    s=json.dumps(j, ensure_ascii=False)
    print("json_ok=True has_VSP_CI=", ("VSP_CI_" in s))
except Exception as e:
    print("json_ok=False err=", e)
PY

echo "[OK] P94 done. Evidence: $EVID"
