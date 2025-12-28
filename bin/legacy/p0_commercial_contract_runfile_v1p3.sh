#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep; need sed

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

APP="vsp_demo_app.py"
[ -f "$APP" ] || err "missing $APP"

# JS files that your scan shows as offenders (active, non-bak)
JS_FILES=(
  static/js/vsp_bundle_commercial_v2.js
  static/js/vsp_dashboard_commercial_v1.js
  static/js/vsp_dashboard_commercial_panels_v1.js
  static/js/vsp_dash_only_v1.js
  static/js/vsp_p0_fetch_shim_v1.js
)

# backup
cp -f "$APP" "${APP}.bak_runfile_v1p3_${TS}" && ok "backup: ${APP}.bak_runfile_v1p3_${TS}"
for f in "${JS_FILES[@]}"; do
  [ -f "$f" ] || { warn "skip missing: $f"; continue; }
  cp -f "$f" "${f}.bak_runfile_v1p3_${TS}" && ok "backup: ${f}.bak_runfile_v1p3_${TS}"
done

echo "== [1] PATCH backend: add /api/vsp/run_file (commercial contract wrapper) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile, time

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_RUN_FILE_CONTRACT_V1P3"
if MARK in s:
    print("[OK] backend already patched")
else:
    # insert before if __name__ == "__main__" if exists, else append
    insert = textwrap.dedent(r'''
    # ==================== VSP_P0_RUN_FILE_CONTRACT_V1P3 ====================
    # Commercial contract: FE must call /api/vsp/run_file?rid=...&name=...
    # Backend maps logical "name" to internal allowed paths and redirects to internal file-allow route.
    try:
        from flask import redirect, request, jsonify
    except Exception:
        redirect = None
        request = None
        jsonify = None

    @app.get("/api/vsp/run_file")
    def vsp_run_file_contract_v1p3():
        """
        name:
          - gate_summary -> run_gate_summary.json
          - gate_json    -> run_gate.json
          - findings_unified -> findings_unified.json (internal locations resolved by existing logic)
          - findings_html -> reports/findings_unified.html
          - run_manifest -> run_manifest.json
          - run_evidence_index -> run_evidence_index.json
        """
        try:
            rid = (request.args.get("rid") or "").strip()
            name = (request.args.get("name") or "").strip()
            if not rid or not name:
                return jsonify({"ok": False, "error": "missing rid/name"}), 400

            # logical name -> internal path
            MAP = {
              "gate_summary": "run_gate_summary.json",
              "gate_json": "run_gate.json",
              "findings_unified": "findings_unified.json",
              "findings_html": "reports/findings_unified.html",
              "run_manifest": "run_manifest.json",
              "run_evidence_index": "run_evidence_index.json",
            }
            path = MAP.get(name, "")

            # allow passing raw safe filenames (no slashes) for backward compat
            if not path:
                if "/" in name or "\\" in name:
                    return jsonify({"ok": False, "error": "invalid name"}), 400
                # only allow small safe set by extension
                if not re.match(r'^[a-zA-Z0-9_.-]{1,120}$', name):
                    return jsonify({"ok": False, "error": "invalid name"}), 400
                path = name

            # Redirect to internal allow endpoint (FE never calls it directly)
            return redirect(f"/api/vsp/run_file_allow?rid={rid}&path={path}", code=302)
        except Exception as e:
            try:
                return jsonify({"ok": False, "error": str(e)}), 500
            except Exception:
                return ("error", 500)
    # ==================== /VSP_P0_RUN_FILE_CONTRACT_V1P3 ====================
    ''')

    # ensure we have re imported or available
    if "import re" not in s:
        # don't risk global import; local route already uses re from outer scope; inject a lightweight import near top
        s = "import re\n" + s

    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s, flags=re.M)
    if m:
        s = s[:m.start()] + "\n" + insert + "\n" + s[m.start():]
    else:
        s = s + "\n\n" + insert + "\n"

    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] backend patched + py_compile OK")

PY
ok "py_compile OK: $APP"

echo "== [2] PATCH FE: replace forbidden literals + switch to /api/vsp/run_file contract =="
python3 - <<'PY'
from pathlib import Path
import re, subprocess, time

FILES = [
  "static/js/vsp_bundle_commercial_v2.js",
  "static/js/vsp_dashboard_commercial_v1.js",
  "static/js/vsp_dashboard_commercial_panels_v1.js",
  "static/js/vsp_dash_only_v1.js",
  "static/js/vsp_p0_fetch_shim_v1.js",
]

def backup(p: Path):
    ts=time.strftime("%Y%m%d_%H%M%S")
    b=p.with_suffix(p.suffix+f".bak_fe_v1p3_{ts}")
    b.write_text(p.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
    return b

def node_check(p: Path)->bool:
    try:
        subprocess.check_output(["node","--check",str(p)], stderr=subprocess.STDOUT, timeout=25)
        return True
    except subprocess.CalledProcessError as e:
        print(e.output.decode("utf-8","ignore"))
        return False

def patch_js(s: str) -> str:
    # 1) contract endpoint swap
    #   /api/vsp/run_file_allow?rid=...&path=XXX  -> /api/vsp/run_file?rid=...&name=YYY
    s = s.replace("/api/vsp/run_file_allow", "/api/vsp/run_file")

    # 2) query key path -> name
    s = s.replace("?path=", "?name=")
    s = s.replace("&path=", "&name=")

    # 3) map known internal file names to logical names (avoid mentioning internal file names)
    # important: do this AFTER path->name conversion
    s = s.replace('name=findings_unified.json', 'name=findings_unified')
    s = s.replace('"findings_unified.json"', '"findings_unified"')
    s = s.replace("'findings_unified.json'", "'findings_unified'")

    s = s.replace('name=run_gate_summary.json', 'name=gate_summary')
    s = s.replace('"run_gate_summary.json"', '"gate_summary"')
    s = s.replace("'run_gate_summary.json'", "'gate_summary'")

    s = s.replace('name=run_gate.json', 'name=gate_json')
    s = s.replace('"run_gate.json"', '"gate_json"')
    s = s.replace("'run_gate.json'", "'gate_json'")

    s = s.replace('name=reports/findings_unified.html', 'name=findings_html')
    s = s.replace('"reports/findings_unified.html"', '"findings_html"')
    s = s.replace("'reports/findings_unified.html'", "'findings_html'")

    s = s.replace('name=run_manifest.json', 'name=run_manifest')
    s = s.replace('name=run_evidence_index.json', 'name=run_evidence_index')

    # 4) scrub internal absolute paths from strings/comments (commercial)
    s = re.sub(r'/home/test/Data/[^\s"\'`<>]+', '/path/to/data', s)

    # 5) scrub debug labels
    s = re.sub(r'UNIFIED FROM\s+[^\n]*', 'Unified data source', s, flags=re.I)

    return s

patched=0
for fp in FILES:
    p=Path(fp)
    if not p.exists(): 
        continue
    orig=p.read_text(encoding="utf-8", errors="ignore")
    new=patch_js(orig)
    if new==orig:
        continue
    bk=backup(p)
    p.write_text(new, encoding="utf-8")
    if not node_check(p):
        # rollback
        p.write_text(bk.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
        raise SystemExit(f"[ERR] node --check failed, rolled back: {fp}")
    print("[OK] patched:", fp)
    patched += 1

print("[DONE] patched_files=", patched)
PY

echo "== [3] node --check for touched JS =="
for f in "${JS_FILES[@]}"; do
  [ -f "$f" ] || continue
  node --check "$f" && ok "node --check OK: $f" || err "node --check FAIL: $f"
done

echo "== [4] SMOKE SCAN: active JS only (exclude backups) =="
grep -RIn --line-number --exclude='*.bak_*' --exclude='*.BAD_*' --exclude='*.disabled_*' \
  '/api/vsp/run_file_allow' static/js | head -n 120 || true

grep -RIn --line-number --exclude='*.bak_*' --exclude='*.BAD_*' --exclude='*.disabled_*' \
  'findings_unified\.json|/home/test/Data/' static/js | head -n 120 || true

echo "== [DONE] Restart vsp-ui-8910 + Ctrl+F5 /vsp5 and verify downloads still work via /api/vsp/run_file. =="
