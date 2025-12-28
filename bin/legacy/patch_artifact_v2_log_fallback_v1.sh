#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_artv2_fallback_${TS}"
echo "[BACKUP] $F.bak_artv2_fallback_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "# === VSP ARTIFACT V2 LOG FALLBACK V1 ==="
if MARK in txt:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert helper + enhance vsp_run_artifact_v2: when asking runner.log and not found -> choose best available
inject = r'''
# === VSP ARTIFACT V2 LOG FALLBACK V1 ===
def _pick_best_log(ci_dir: str) -> str:
    """
    Return relative path of best log inside ci_dir.
    Priority:
      1) runner.log / runner*.log
      2) out_ci/*.log
      3) tool logs commonly used
    """
    try:
        base = Path(ci_dir)
        if not base.exists():
            return "runner.log"
        # exact / runner*
        for cand in ["runner.log", "runner_outer.log", "ui_8910.log", "ci_runner.log"]:
            if (base / cand).exists():
                return cand
        # glob runner*.log
        gl = sorted(base.glob("runner*.log"), key=lambda x: x.stat().st_mtime, reverse=True)
        if gl:
            return gl[0].name
        # out_ci/*.log
        out_ci = base / "out_ci"
        if out_ci.exists():
            gl2 = sorted(out_ci.glob("*.log"), key=lambda x: x.stat().st_mtime, reverse=True)
            if gl2:
                return str(gl2[0].relative_to(base))
        # common tool logs
        candidates = [
            "kics/kics.log",
            "semgrep/semgrep.log",
            "codeql/codeql.log",
            "gitleaks/gitleaks.log",
            "trivy/trivy.log",
            "unify/unify.log",
        ]
        for c in candidates:
            if (base / c).exists():
                return c
    except Exception:
        pass
    return "runner.log"
# === END VSP ARTIFACT V2 LOG FALLBACK V1 ===
'''

# Put helper right after STATUS+ARTIFACT V2 block end (safe)
pos = txt.rfind("# === END VSP STATUS+ARTIFACT V2 ===")
if pos == -1:
    raise SystemExit("[ERR] cannot find STATUS+ARTIFACT V2 block end marker")
txt2 = txt[:pos+len("# === END VSP STATUS+ARTIFACT V2 ===")] + "\n" + inject + "\n" + txt[pos+len("# === END VSP STATUS+ARTIFACT V2 ==="):]

# Now patch inside vsp_run_artifact_v2: before returning 404, if rel == runner.log -> retry with best log
pat = r'return jsonify\(\{"ok": False, "rid": rid, "error": "artifact_not_found"[\s\S]*?\}\), 404'
m = re.search(pat, txt2)
if not m:
    raise SystemExit("[ERR] cannot locate artifact_not_found return block in vsp_run_artifact_v2")

replacement = r'''
    # fallback for runner.log -> best available log
    if rel in ("runner.log", "runner_outer.log", "ui_8910.log"):
        best = _pick_best_log(ci_dir) if ci_dir else ""
        if best and best != rel:
            try:
                fp2 = _safe_join(Path(ci_dir), best)
                if fp2.exists() and fp2.is_file():
                    return Response(fp2.read_bytes(), status=200, mimetype=_guess_mime(best))
            except Exception:
                pass

    return jsonify({"ok": False, "rid": rid, "error": "artifact_not_found", "path": rel}), 404
'''
txt2 = re.sub(pat, replacement, txt2, count=1)

p.write_text(txt2, encoding="utf-8")
print("[OK] patched artifact_v2 fallback for logs")
PY

/home/test/Data/SECURITY_BUNDLE/.venv/bin/python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile"
sudo systemctl restart vsp-ui-8910
sudo systemctl restart vsp-ui-8911-dev
