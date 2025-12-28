#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

FILES=(wsgi_vsp_ui_gateway.py vsp_demo_app.py)
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
done

TS="$(date +%Y%m%d_%H%M%S)"
for f in "${FILES[@]}"; do
  cp -f "$f" "${f}.bak_vmanifest_v4_${TS}"
  echo "[BACKUP] ${f}.bak_vmanifest_v4_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re, textwrap

MARK = "VSP_P0_VIRTUAL_MANIFEST_EVIDENCEINDEX_DUALPATCH_V4"
INJECT_MARK = "VSP_P0_VIRTUAL_MANIFEST_EVIDENCEINDEX_DUALPATCH_V4_INJECT"

HELPER = r"""
# ===================== __MARK__ =====================
import os, json, time
from pathlib import Path as _VSPPath
from flask import Response, request, send_file

def _vsp_p0_runs_roots():
    roots = []
    one = os.environ.get("VSP_RUNS_ROOT", "").strip()
    if one:
        roots.append(one)
    many = os.environ.get("VSP_RUNS_ROOTS", "").strip()
    if many:
        for x in many.split(":"):
            x = x.strip()
            if x:
                roots.append(x)

    roots += [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]

    out, seen = [], set()
    for r in roots:
        if r not in seen:
            seen.add(r)
            out.append(r)
    return out

def _vsp_p0_try_resolve_gate_root_path(rid, gate_root_name):
    if not rid:
        return None
    if not gate_root_name:
        gate_root_name = f"gate_root_{rid}"

    for base in _vsp_p0_runs_roots():
        try:
            b = _VSPPath(base)
            if not b.is_dir():
                continue

            cand = b / gate_root_name
            if cand.is_dir():
                return str(cand)

            # 1 level
            for d1 in b.iterdir():
                if d1.is_dir():
                    c1 = d1 / gate_root_name
                    if c1.is_dir():
                        return str(c1)

            # 2 levels (bounded)
            for d1 in b.iterdir():
                if not d1.is_dir():
                    continue
                try:
                    for d2 in d1.iterdir():
                        if d2.is_dir():
                            c2 = d2 / gate_root_name
                            if c2.is_dir():
                                return str(c2)
                except Exception:
                    continue
        except Exception:
            continue
    return None

def _vsp_p0_virtual_manifest(rid, gate_root_name, gate_root_path, served_by):
    now = int(time.time())
    return {
        "ok": True,
        "rid": rid,
        "gate_root": gate_root_name,
        "gate_root_path": gate_root_path,
        "generated": True,
        "generated_at": now,
        "degraded": (gate_root_path is None),
        "served_by": served_by,
        "required_paths": [
            "run_gate.json",
            "run_gate_summary.json",
            "findings_unified.json",
            "reports/findings_unified.csv",
            "run_manifest.json",
            "run_evidence_index.json",
        ],
        "optional_paths": [
            "reports/findings_unified.sarif",
            "reports/findings_unified.html",
            "reports/findings_unified.pdf",
        ],
        "hints": {
            "set_env": "Set VSP_RUNS_ROOT or VSP_RUNS_ROOTS (colon-separated) to the parent folder that contains gate_root_<RID> directories.",
            "example": "VSP_RUNS_ROOT=/home/test/Data/SECURITY-10-10-v4/out_ci",
        },
    }

def _vsp_p0_virtual_evidence_index(rid, gate_root_name, gate_root_path, served_by):
    now = int(time.time())
    evidence_files = []
    evidence_dir = None

    if gate_root_path:
        for sub in ("evidence", "artifacts", "out/evidence"):
            ed = _VSPPath(gate_root_path) / sub
            if ed.is_dir():
                evidence_dir = str(ed)
                try:
                    for fp in sorted(ed.rglob("*")):
                        if fp.is_file():
                            evidence_files.append(str(fp.relative_to(ed)))
                except Exception:
                    pass
                break

    return {
        "ok": True,
        "rid": rid,
        "gate_root": gate_root_name,
        "gate_root_path": gate_root_path,
        "generated": True,
        "generated_at": now,
        "degraded": (gate_root_path is None),
        "served_by": served_by,
        "evidence_dir": evidence_dir,
        "files": evidence_files,
        "missing_recommended": [
            "evidence/ui_engine.log",
            "evidence/trace.zip",
            "evidence/last_page.html",
            "evidence/storage_state.json",
            "evidence/net_summary.json",
        ],
    }
# ===================== /__MARK__ =====================
""".strip("\n").replace("__MARK__", MARK)

INJECT = r"""
# ===== __INJECT__ =====
_rid = request.args.get("rid", "") or request.args.get("RID", "")
_path = request.args.get("path", "") or request.args.get("PATH", "")

if _path in ("run_manifest.json", "run_evidence_index.json"):
    _gate_root_name = f"gate_root_{_rid}" if _rid else None
    _gate_root_path = _vsp_p0_try_resolve_gate_root_path(_rid, _gate_root_name)

    # Prefer real file if present
    if _gate_root_path:
        _real = _VSPPath(_gate_root_path) / _path
        if _real.is_file():
            try:
                return send_file(str(_real))
            except Exception:
                pass

    served_by = __file__ if "__file__" in globals() else "unknown"
    if _path == "run_manifest.json":
        payload = _vsp_p0_virtual_manifest(_rid, _gate_root_name, _gate_root_path, served_by)
    else:
        payload = _vsp_p0_virtual_evidence_index(_rid, _gate_root_name, _gate_root_path, served_by)

    return Response(json.dumps(payload, ensure_ascii=False, indent=2), status=200, mimetype="application/json")
# ===== /__INJECT__ =====
""".strip("\n").replace("__INJECT__", INJECT_MARK)

def patch_file(path: Path):
    s = path.read_text(encoding="utf-8", errors="replace")

    # 1) ensure helper exists
    if MARK not in s:
        m = re.search(r'^(?:from[^\n]+\n|import[^\n]+\n)+', s, flags=re.M)
        if m:
            s = s[:m.end()] + "\n" + HELPER + "\n\n" + s[m.end():]
        else:
            s = HELPER + "\n\n" + s

    # 2) locate handler function for /api/vsp/run_file_allow
    fn = None

    # (A) add_url_rule(...)
    m = re.search(r'add_url_rule\(\s*[\'"]/api/vsp/run_file_allow[\'"]\s*,\s*[\'"][^\'"]+[\'"]\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
    if m:
        fn = m.group(1)
    else:
        # (B) decorator @app.route("/api/vsp/run_file_allow"...)
        dm = re.search(r'@.*route\(\s*[\'"]/api/vsp/run_file_allow[\'"]', s)
        if dm:
            after = s[dm.end(): dm.end() + 800]
            m2 = re.search(r'\ndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', after)
            if m2:
                fn = m2.group(1)

    if not fn:
        print("[WARN] cannot find run_file_allow handler in", path.name)
        return s, False, None

    # 3) inject at top of def body
    def_pat = re.compile(rf'(def\s+{re.escape(fn)}\s*\([^)]*\)\s*:\n)', re.M)
    dm2 = def_pat.search(s)
    if not dm2:
        print("[WARN] cannot find def for", fn, "in", path.name)
        return s, False, fn

    window = s[dm2.end(): dm2.end() + 2500]
    if INJECT_MARK in window:
        return s, True, fn

    # indent from next indented line, fallback 4 spaces
    after = s[dm2.end(): dm2.end() + 400]
    m_ind = re.search(r'\n([ \t]+)\S', after)
    indent = m_ind.group(1) if m_ind else "    "

    inj = "\n".join((indent + ln) if ln else ln for ln in INJECT.split("\n")) + "\n"
    s = s[:dm2.end()] + inj + s[dm2.end():]
    return s, True, fn

changed = False
for fname in ("wsgi_vsp_ui_gateway.py", "vsp_demo_app.py"):
    path = Path(fname)
    new_s, ok, fn = patch_file(path)
    if ok:
        path.write_text(new_s, encoding="utf-8")
        print("[OK] patched", fname, "handler=", fn)
        changed = True
    else:
        print("[WARN] no patch applied for", fname)

if not changed:
    raise SystemExit("[ERR] nothing patched")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("rid",""))' || true)"
echo "RID=$RID"
RID="${RID:-VSP_CI_20251219_092640}"

for p in run_manifest.json run_evidence_index.json; do
  echo "== $p =="
  curl -sS -o "/tmp/vsp_${p}.out" -w "HTTP=%{http_code}\n" "$BASE/api/vsp/run_file_allow?rid=${RID}&path=$p"
  head -n 20 "/tmp/vsp_${p}.out" | sed -e 's/\r$//'
done

echo "[DONE] Expect HTTP=200 + JSON includes served_by + degraded flag."
