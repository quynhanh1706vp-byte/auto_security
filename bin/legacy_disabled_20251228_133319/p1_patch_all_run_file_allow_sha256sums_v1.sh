#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P1_ALLOW_SHA256SUMS_GLOBAL_V1"

python3 - <<'PY'
import os, re, shutil
from pathlib import Path

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
TS = os.environ.get("TS","")
MARK = "VSP_P1_ALLOW_SHA256SUMS_GLOBAL_V1"

cands=[]
for p in ROOT.rglob("*.py"):
    try:
        s=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "/api/vsp/run_file" in s and ("not allowed" in s or "NOT_ALLOWED" in s):
        cands.append(p)

print("[INFO] candidates:", len(cands))
for p in cands:
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[SKIP] already:", p)
        continue

    bak = p.with_suffix(p.suffix + f".bak_sha_all_{TS}")
    shutil.copy2(p, bak)
    print("[BACKUP]", bak)

    # 1) Try extend allowlist by adding reports/SHA256SUMS.txt next to reports/SUMMARY.txt if present
    changed=False
    if "reports/SUMMARY.txt" in s and "reports/SHA256SUMS.txt" not in s:
        s2 = s.replace('"reports/SUMMARY.txt"', '"reports/SUMMARY.txt", "reports/SHA256SUMS.txt"', 1)
        if s2 == s:
            s2 = s.replace("'reports/SUMMARY.txt'", "('reports/SUMMARY.txt', 'reports/SHA256SUMS.txt')", 1)
        if s2 != s:
            s = s2
            changed=True
            print("[OK] allowlist extended in", p.name)

    # 2) If still not changed, inject bypass right BEFORE the first return that contains "not allowed"
    if not changed:
        m = re.search(r'^[ \t]*return[^\n]*not allowed[^\n]*$', s, flags=re.M)
        if not m:
            m = re.search(r'^[ \t]*return[^\n]*["\']not allowed["\'][^\n]*$', s, flags=re.M)

        if m:
            inject = f'''
    # {MARK}: allow reports/SHA256SUMS.txt (commercial audit)
    try:
        _rid = (request.args.get("rid","") or request.args.get("run_id","") or request.args.get("run","") or request.args.get("run_id","") or "").strip()
        _rel = (request.args.get("name","") or request.args.get("path","") or request.args.get("rel","") or "").strip().lstrip("/")
        if _rid and _rel == "reports/SHA256SUMS.txt":
            from pathlib import Path as _P
            from flask import send_file as _send_file, jsonify as _jsonify
            _roots = [
                _P("/home/test/Data/SECURITY_BUNDLE/out"),
                _P("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                _P("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
                _P("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            ]
            for _root in _roots:
                _fp = _root / _rid / "reports" / "SHA256SUMS.txt"
                if _fp.exists():
                    return _send_file(str(_fp), as_attachment=True)
            return _jsonify({{"ok": False, "error": "NO_FILE"}}), 404
    except Exception:
        pass
'''
            s = s[:m.start()] + inject + s[m.start():]
            changed=True
            print("[OK] bypass injected in", p.name)

    if not changed:
        print("[WARN] could not patch:", p)
        continue

    s += f"\n# {MARK}\n"
    p.write_text(s, encoding="utf-8")

print("[DONE] patch pass finished")
PY

echo "== py_compile all touched candidates =="
python3 - <<'PY'
import os
from pathlib import Path
ROOT=Path("/home/test/Data/SECURITY_BUNDLE/ui")
bad=[]
for p in ROOT.rglob("*.py"):
    if ".bak_sha_all_" in p.name: 
        continue
    try:
        import py_compile
        py_compile.compile(str(p), doraise=True)
    except Exception as e:
        bad.append((str(p), str(e)))
if bad:
    print("[ERR] py_compile failures:")
    for f,e in bad[:20]:
        print(" -", f, e)
    raise SystemExit(2)
print("[OK] py_compile OK")
PY

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 25
