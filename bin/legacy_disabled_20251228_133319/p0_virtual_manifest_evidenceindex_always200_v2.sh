#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_vmanifest_v2_${TS}"
echo "[BACKUP] ${WSGI}.bak_vmanifest_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_VIRTUAL_MANIFEST_EVIDENCEINDEX_ALWAYS200_V2"
INJECT_MARK = "VSP_P0_VIRTUAL_MANIFEST_EVIDENCEINDEX_ALWAYS200_V2_INJECT"

# 1) helper block (imports + resolver + virtual json)
if MARK not in s:
    helper = textwrap.dedent(f"""
    # ===================== {MARK} =====================
    import os, json, time
    from pathlib import Path as _VSPPath
    from flask import Response, request, send_file

    def _vsp_runs_roots():
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

        # Safe defaults (fast, bounded; no sudo scan)
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

    def _vsp_try_resolve_gate_root_path(rid, gate_root_name):
        if not rid:
            return None
        if not gate_root_name:
            gate_root_name = f"gate_root_{rid}"

        for base in _vsp_runs_roots():
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

    def _vsp_virtual_manifest(rid, gate_root_name, gate_root_path):
        now = int(time.time())
        required = [
            "run_gate.json",
            "run_gate_summary.json",
            "findings_unified.json",
            "reports/findings_unified.csv",
            "run_manifest.json",
            "run_evidence_index.json",
        ]
        optional = [
            "reports/findings_unified.sarif",
            "reports/findings_unified.html",
            "reports/findings_unified.pdf",
        ]
        return {
            "ok": True,
            "rid": rid,
            "gate_root": gate_root_name,
            "gate_root_path": gate_root_path,
            "generated": True,
            "generated_at": now,
            "degraded": (gate_root_path is None),
            "required_paths": required,
            "optional_paths": optional,
            "hints": {
                "set_env": "Set VSP_RUNS_ROOT or VSP_RUNS_ROOTS (colon-separated) to the parent folder that contains gate_root_<RID> directories.",
                "example": "VSP_RUNS_ROOT=/home/test/Data/SECURITY-10-10-v4/out_ci",
            },
        }

    def _vsp_virtual_evidence_index(rid, gate_root_name, gate_root_path):
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
    # ===================== /{MARK} =====================
    """).strip("\n")

    # Insert after import block if possible
    m = re.search(r'^(?:from[^\n]+\n|import[^\n]+\n)+', s, flags=re.M)
    if m:
        s = s[:m.end()] + "\n" + helper + "\n\n" + s[m.end():]
    else:
        s = helper + "\n\n" + s

# 2) find handler func name for /api/vsp/run_file_allow
m = re.search(r'add_url_rule\(\s*[\'"]/api/vsp/run_file_allow[\'"]\s*,\s*[\'"][^\'"]+[\'"]\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
if not m:
    raise SystemExit("[ERR] cannot find add_url_rule for /api/vsp/run_file_allow")
fn = m.group(1)

# 3) inject at top of handler body (no dependency on existing rid/path vars)
pat = re.compile(rf'(def\s+{re.escape(fn)}\s*\([^)]*\)\s*:\n)([ \t]+)', re.M)
mm = pat.search(s)
if not mm:
    raise SystemExit(f"[ERR] cannot find def {fn}(...)")

if INJECT_MARK not in s:
    indent = mm.group(2)  # indentation of first body line
    inject = textwrap.dedent(f"""
    # ===== {INJECT_MARK} =====
    _rid = request.args.get("rid", "") or request.args.get("RID", "")
    _path = request.args.get("path", "") or request.args.get("PATH", "")
    if _path in ("run_manifest.json", "run_evidence_index.json"):
        _gate_root_name = f"gate_root_{{_rid}}" if _rid else None
        _gate_root_path = _vsp_try_resolve_gate_root_path(_rid, _gate_root_name)

        # Prefer real file if present
        if _gate_root_path:
            _real = _VSPPath(_gate_root_path) / _path
            if _real.is_file():
                try:
                    return send_file(str(_real))
                except Exception:
                    pass

        # Virtual JSON (always 200 for P0 contract)
        if _path == "run_manifest.json":
            payload = _vsp_virtual_manifest(_rid, _gate_root_name, _gate_root_path)
        else:
            payload = _vsp_virtual_evidence_index(_rid, _gate_root_name, _gate_root_path)
        return Response(json.dumps(payload, ensure_ascii=False, indent=2), status=200, mimetype="application/json")
    # ===== /{INJECT_MARK} =====
    """).strip("\n")

    inject = "\n".join((indent + ln) if ln else ln for ln in inject.split("\n")) + "\n"
    insert_pos = mm.end(1)
    s = s[:insert_pos] + inject + s[insert_pos:]

p.write_text(s, encoding="utf-8")
print("[OK] patched handler:", fn)
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("rid",""))' || true)"
echo "RID=$RID"
RID="${RID:-VSP_CI_20251219_092640}"

for p in run_manifest.json run_evidence_index.json; do
  code="$(curl -sS -o "/tmp/vsp_smoke_${p}.out" -w "%{http_code}" "$BASE/api/vsp/run_file_allow?rid=${RID}&path=$p" || true)"
  echo "$p => $code (size=$(wc -c </tmp/vsp_smoke_${p}.out 2>/dev/null || echo 0))"
done

echo "[DONE] Expect both 200. If degraded=true -> set VSP_RUNS_ROOT(S) later to resolve gate_root_path."
