#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need systemctl; need curl; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

JS_LIST=(
  "static/js/vsp_runs_reports_overlay_v1.js"
  "static/js/vsp_runs_kpi_compact_v3.js"
  "static/js/vsp_runs_quick_actions_v1.js"
)

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_allow2_${TS}"
echo "[BACKUP] ${W}.bak_allow2_${TS}"

for f in "${JS_LIST[@]}"; do
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_allow2_${TS}"
    echo "[BACKUP] ${f}.bak_allow2_${TS}"
  else
    echo "[WARN] missing JS: $f (skip)"
  fi
done

python3 - <<'PY'
from pathlib import Path
import re, textwrap

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUN_FILE_ALLOW2_NO403_V1"
if marker not in s:
    block = textwrap.dedent(r'''
    # ===================== VSP_P2_RUN_FILE_ALLOW2_NO403_V1 =====================
    # New endpoint to avoid 403 spam and to explicitly allow gate summaries under reports/.
    # Always returns HTTP 200 with ok=false on errors (commercial-grade: no noisy 403 in console).
    try:
        from flask import jsonify, request, send_file
    except Exception:
        jsonify = None
        request = None
        send_file = None

    def _vsp_allow2_roots_v1():
        # prefer same roots used by /api/vsp/runs (best-effort)
        roots = []
        for r in (
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/ui/out",
        ):
            try:
                if Path(r).exists():
                    roots.append(r)
            except Exception:
                pass
        return roots

    def _vsp_allow2_resolve_run_dir_v1(rid: str):
        # fast path: root/rid
        rid = (rid or "").strip()
        if not rid:
            return None
        for root in _vsp_allow2_roots_v1():
            p = Path(root) / rid
            if p.is_dir():
                return str(p)
        # fallback (very limited): search 1-level deep only
        for root in _vsp_allow2_roots_v1():
            base = Path(root)
            try:
                for child in base.iterdir():
                    if child.is_dir() and child.name == rid:
                        return str(child)
            except Exception:
                continue
        return None

    def _vsp_allow2_allowed_paths_v1():
        # Explicit allowlist (extend safely here)
        return set([
            "SUMMARY.txt",
            "run_gate.json",
            "run_gate_summary.json",
            "reports/run_gate.json",
            "reports/run_gate_summary.json",
            "findings_unified.json",
            "findings_unified.sarif",
            "reports/findings_unified.csv",
            "reports/findings_unified.html",
            "reports/findings_unified.tgz",
            "reports/findings_unified.zip",
            # keep compatibility with older names if any
            "reports/run_gate_summary.json",
        ])

    @app.get("/api/vsp/run_file_allow2")
    def _vsp_run_file_allow2_v1():
        try:
            if request is None or jsonify is None:
                return '{"ok":false,"err":"flask missing"}', 200, {"Content-Type":"application/json"}
            rid = (request.args.get("rid","") or "").strip()
            rel = (request.args.get("path","") or "").strip().lstrip("/")
            if not rid or not rel:
                return jsonify(ok=False, err="missing rid/path"), 200

            allow = _vsp_allow2_allowed_paths_v1()
            if rel not in allow:
                return jsonify(ok=False, err="not allowed", allow=sorted(list(allow))[:200]), 200

            run_dir = _vsp_allow2_resolve_run_dir_v1(rid)
            if not run_dir:
                return jsonify(ok=False, err="run dir not found", rid=rid, roots=_vsp_allow2_roots_v1()), 200

            fp = Path(run_dir) / rel
            if not fp.exists() or not fp.is_file():
                return jsonify(ok=False, err="file not found", rid=rid, path=rel), 200

            # Serve file content
            # Let browser/json parser handle it; no 403/404 noise.
            return send_file(str(fp), as_attachment=False, download_name=fp.name), 200
        except Exception as e:
            try:
                return jsonify(ok=False, err=str(e)), 200
            except Exception:
                return '{"ok":false,"err":"internal"}', 200, {"Content-Type":"application/json"}

    # ===================== /VSP_P2_RUN_FILE_ALLOW2_NO403_V1 =====================
    ''').strip("\n")

    # append near end of file (safe)
    s = s.rstrip() + "\n\n" + block + "\n"
    w.write_text(s, encoding="utf-8")
    print("[OK] appended allow2 endpoint block")
else:
    print("[OK] allow2 block already exists (skip append)")

# Rewire JS: run_file_allow -> run_file_allow2
js_files = [
  Path("static/js/vsp_runs_reports_overlay_v1.js"),
  Path("static/js/vsp_runs_kpi_compact_v3.js"),
  Path("static/js/vsp_runs_quick_actions_v1.js"),
]
changed = 0
for p in js_files:
    if not p.exists():
        continue
    txt = p.read_text(encoding="utf-8", errors="replace")
    txt2, n = re.subn(r'/api/vsp/run_file_allow\b', '/api/vsp/run_file_allow2', txt)
    if n:
        p.write_text(txt2, encoding="utf-8")
        changed += n
        print(f"[OK] rewired {p}: n={n}")
print(f"[OK] total JS rewires: {changed}")
PY

python3 -m py_compile "$W" && echo "[OK] py_compile OK"

for f in "${JS_LIST[@]}"; do
  [ -f "$f" ] && node --check "$f" && echo "[OK] node --check $f"
done

echo "== restart =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.9

echo "== sanity allow2 =="
RID="RUN_20251120_130310"
curl -sS -i "$BASE/api/vsp/run_file_allow2?rid=$RID&path=reports/run_gate_summary.json" | head -n 25 || true

echo "[DONE] Hard reload /runs (Ctrl+Shift+R). Console 403 spam should disappear."
