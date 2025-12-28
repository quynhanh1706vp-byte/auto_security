#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_status_fs_${TS}"
echo "[BACKUP] $F.bak_status_fs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK_BEG = "# === VSP RUN_STATUS FS RESOLVER V2 ==="
MARK_END = "# === END VSP RUN_STATUS FS RESOLVER V2 ==="
if MARK_BEG in txt:
    print("[OK] already patched")
    sys.exit(0)

block = r'''
# === VSP RUN_STATUS FS RESOLVER V2 ===
import os, json, time, glob
from pathlib import Path
from flask import jsonify

def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="ignore") or "{}")
    except Exception:
        return None

def _find_ci_run_dir_by_rid(rid: str):
    """
    Resolve rid -> ci_run_dir robustly.
    Supports:
      - RUN_VSP_CI_YYYYmmdd_HHMMSS (points to /home/test/Data/SECURITY-10-10-v4/out_ci/<RID>)
      - VSP_CI_YYYYmmdd_HHMMSS
      - VSP_UIREQ_YYYYmmdd_HHMMSS_xxx (look under ui/out_ci/uireq_v1/<rid>.json for ci_run_dir)
    """
    if not rid:
        return None

    # 1) If uireq state exists, trust its ci_run_dir
    try:
        uireq = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1") / f"{rid}.json"
        if uireq.exists():
            j = _read_json(uireq) or {}
            cd = j.get("ci_run_dir") or j.get("ci_dir")
            if cd and Path(cd).exists():
                return cd
    except Exception:
        pass

    # 2) Direct known CI roots (search a few common places)
    candidates = []

    # primary demo env root (you used it)
    candidates.append(Path("/home/test/Data/SECURITY-10-10-v4/out_ci") / rid)

    # sometimes rid inside ci dir without RUN_ prefix
    if rid.startswith("RUN_"):
        candidates.append(Path("/home/test/Data/SECURITY-10-10-v4/out_ci") / rid.replace("RUN_", "", 1))
    else:
        candidates.append(Path("/home/test/Data/SECURITY-10-10-v4/out_ci") / ("RUN_" + rid))

    # optional: SECURITY_BUNDLE out (if you also run locally there)
    candidates.append(Path("/home/test/Data/SECURITY_BUNDLE/out_ci") / rid)
    candidates.append(Path("/home/test/Data/SECURITY_BUNDLE/out") / rid)

    for c in candidates:
        try:
            if c.exists() and c.is_dir():
                return str(c)
        except Exception:
            pass

    # 3) Last resort: glob scan by prefix timestamp (bounded)
    # If rid includes YYYYmmdd_HHMMSS pattern, try matching folders quickly
    m = re.search(r"(20\d{6}_\d{6})", rid)
    if m:
        ts = m.group(1)
        globs = [
            f"/home/test/Data/SECURITY-10-10-v4/out_ci/*{ts}*",
            f"/home/test/Data/SECURITY_BUNDLE/out_ci/*{ts}*",
        ]
        for g in globs:
            for path in sorted(glob.glob(g), reverse=True)[:20]:
                try:
                    if Path(path).is_dir():
                        return str(Path(path))
                except Exception:
                    continue
    return None

def _read_degraded_tools(ci_run_dir: str):
    if not ci_run_dir:
        return []
    fp = Path(ci_run_dir) / "degraded_tools.json"
    if fp.exists():
        j = _read_json(fp)
        if isinstance(j, list):
            return j
        if isinstance(j, dict) and isinstance(j.get("degraded_tools"), list):
            return j["degraded_tools"]
    return []

# Wrap/override run_status endpoint output at app level
try:
    _orig_run_status_v1 = vsp_run_api_v1.run_status_v1  # type: ignore
except Exception:
    _orig_run_status_v1 = None

@app.get("/api/vsp/run_status_v1/<rid>")
def vsp_run_status_v1_fs_resolver(rid):
    """
    Commercial status:
      - always returns degraded_tools as list
      - always returns ci_run_dir if resolvable
    """
    base = {}
    # 1) try original handler (if any)
    try:
        if _orig_run_status_v1:
            resp = _orig_run_status_v1(rid)
            # resp could be (jsonify, code) or Response
            payload = None
            code = 200
            if isinstance(resp, tuple):
                payload = resp[0].get_json(silent=True) if hasattr(resp[0], "get_json") else None
                code = resp[1] if len(resp) > 1 else 200
            else:
                payload = resp.get_json(silent=True) if hasattr(resp, "get_json") else None
            if isinstance(payload, dict):
                base = payload
                base.setdefault("ok", True)
                base.setdefault("rid", rid)
                # let it pass through; we'll normalize below
    except Exception as e:
        base = {"ok": False, "rid": rid, "error": str(e)}

    # 2) FS resolve ci_run_dir if missing
    ci_dir = base.get("ci_run_dir") or base.get("ci_dir")
    if not ci_dir:
        ci_dir = _find_ci_run_dir_by_rid(rid)
        if ci_dir:
            base["ci_run_dir"] = ci_dir

    # 3) normalize degraded_tools
    dt = base.get("degraded_tools")
    if not isinstance(dt, list):
        dt = _read_degraded_tools(ci_dir) if ci_dir else []
    base["degraded_tools"] = dt

    # 4) ok/final/finish_reason normalization
    if base.get("ci_run_dir"):
        base["ok"] = True
    else:
        base.setdefault("ok", False)
        base.setdefault("error", "ci_run_dir_not_resolved")
    base.setdefault("final", False)
    base.setdefault("finish_reason", "running" if not base.get("final") else "finished")

    return jsonify(base), 200
# === END VSP RUN_STATUS FS RESOLVER V2 ===
'''

# append at end
txt2 = txt.rstrip() + "\n\n" + block + "\n"
p.write_text(txt2, encoding="utf-8")
print("[OK] appended FS resolver V2")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile"
