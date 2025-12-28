#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_run_files_v1_${TS}"
echo "[BACKUP] ${APP}.bak_run_files_v1_${TS}"

python3 - "$APP" <<'PY'
import sys, re, textwrap
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P0_API_RUN_FILES_V1_WHITELIST"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert route near other /api/vsp/* routes.
# We'll look for a stable anchor: an existing route decorator like @app.get("/api/vsp/rid_latest")
m=re.search(r'@app\.(get|route)\(\s*["\']\/api\/vsp\/rid_latest["\']', s)
if not m:
    # fallback: put near top after Flask app creation
    m=re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
    if not m:
        print("[ERR] cannot find insertion point")
        raise SystemExit(2)

ins_pos = m.start()

route=textwrap.dedent(r'''
# --- VSP_P0_API_RUN_FILES_V1_WHITELIST ---
@app.get("/api/vsp/run_files_v1")
def api_vsp_run_files_v1():
    """
    List safe per-run artifact files for a RID (commercial-grade, whitelist).
    Returns only within report/report(s) and a small set of root files.
    """
    import os, time
    from pathlib import Path
    rid = (request.args.get("rid") or "").strip()
    if not rid:
        return jsonify({"ok": False, "err": "missing rid"}), 200

    # Resolve run_dir similarly to other endpoints (best effort).
    run_dir = None
    try:
        # If you already have a helper like _resolve_run_dir(rid), use it:
        if "_resolve_run_dir" in globals():
            run_dir = _resolve_run_dir(rid)
    except Exception:
        run_dir = None

    # fallback: try known roots from existing runs index if present
    if not run_dir:
        roots = []
        try:
            roots = (globals().get("RUN_ROOTS") or [])  # optional
        except Exception:
            roots = []
        # last resort: infer from existing /api/vsp/runs data if helper exists
        if not roots and "_list_runs" in globals():
            try:
                rr = _list_runs(limit=200, offset=0)
                roots = rr.get("roots") or []
            except Exception:
                roots = []
        # common local default
        if not roots:
            roots = ["/home/test/Data/SECURITY_BUNDLE/out", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci", "/home/test/Data/SECURITY_BUNDLE/ui/out"]

        for rt in roots:
            cand = Path(rt) / rid
            if cand.exists() and cand.is_dir():
                run_dir = str(cand)
                break

    if not run_dir:
        return jsonify({"ok": False, "err": "run_dir not found", "rid": rid}), 200

    base = Path(run_dir).resolve()
    # hard safety: no traversal
    if rid not in str(base):
        return jsonify({"ok": False, "err": "invalid rid/path", "rid": rid}), 200

    allow_dirs = ["reports", "report"]
    allow_root = set([
        "run_gate_summary.json", "run_gate.json", "findings_unified.json",
        "verdict_4t.json", "SUMMARY.txt", "run_manifest.json"
    ])

    items=[]
    def add_file(fp: Path, rel: str):
        try:
            st=fp.stat()
            items.append({
                "path": rel.replace("\\","/"),
                "size": int(st.st_size),
                "mtime": int(st.st_mtime),
            })
        except Exception:
            pass

    # root files
    for name in sorted(allow_root):
        fp = base / name
        if fp.exists() and fp.is_file():
            add_file(fp, name)

    # report dirs
    for d in allow_dirs:
        dd = base / d
        if not dd.exists() or not dd.is_dir():
            continue
        for fp in dd.rglob("*"):
            if len(items) >= 300:
                break
            if not fp.is_file():
                continue
            rel = str(fp.relative_to(base))
            # keep only common artifact types
            if not re.search(r'\.(html|pdf|zip|json|sarif|csv|txt|log)$', rel, re.I):
                continue
            add_file(fp, rel)

    # sort by path
    items.sort(key=lambda x: x.get("path",""))
    return jsonify({
        "ok": True,
        "rid": rid,
        "run_dir": str(base),
        "total": len(items),
        "items": items,
        "ts": time.time(),
        "marker": "VSP_P0_API_RUN_FILES_V1_WHITELIST"
    }), 200
# --- /VSP_P0_API_RUN_FILES_V1_WHITELIST ---

''')

s = s[:ins_pos] + route + s[ins_pos:]
p.write_text(s, encoding="utf-8")
print("[OK] inserted run_files_v1 route")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

echo "== quick smoke =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/run_files_v1?rid=$RID" | head -c 400; echo
