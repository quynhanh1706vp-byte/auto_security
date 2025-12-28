#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runstatusv2_winlast_v3_${TS}"
echo "[BACKUP] $F.bak_runstatusv2_winlast_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Remove older injected blocks (avoid patch-chồng)
t = re.sub(r"\n# === VSP_ADD_RUN_STATUS_V2_FALLBACK_V1 ===.*?# === END VSP_ADD_RUN_STATUS_V2_FALLBACK_V1 ===\n",
           "\n", t, flags=re.S)
t = re.sub(r"\n# === VSP_ADD_RUN_STATUS_V2_FALLBACK_WINLAST_V2 ===.*?# === END VSP_ADD_RUN_STATUS_V2_FALLBACK_WINLAST_V2 ===\n",
           "\n", t, flags=re.S)
t = re.sub(r"\n# === VSP_RUN_STATUS_V2_WINLAST_V3 ===.*?# === END VSP_RUN_STATUS_V2_WINLAST_V3 ===\n",
           "\n", t, flags=re.S)

TAG = "# === VSP_RUN_STATUS_V2_WINLAST_V3 ==="
END = "# === END VSP_RUN_STATUS_V2_WINLAST_V3 ==="

BLOCK = r'''
# === VSP_RUN_STATUS_V2_WINLAST_V3 ===
# Commercial harden: always return JSON (never 404), resolve ci_run_dir from RID, inject KICS summary if present.
import os, json, re
from pathlib import Path
from flask import jsonify

_STAGE_RE_V2 = re.compile(r"=+\s*\[\s*(\d+)\s*/\s*(\d+)\s*\]\s*([^\]]+?)\s*\]+", re.IGNORECASE)

def _vsp__read_json_if_exists_v2(p: Path):
    try:
        if p and p.exists() and p.is_file():
            return json.loads(p.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None
    return None

def _vsp__tail_text_v2(p: Path, max_bytes: int = 20000) -> str:
    try:
        if not p.exists() or not p.is_file():
            return ""
        bs = p.read_bytes()
        if len(bs) > max_bytes:
            bs = bs[-max_bytes:]
        return bs.decode("utf-8", errors="ignore")
    except Exception:
        return ""

def _vsp__resolve_ci_run_dir_v2(rid: str):
    # Prefer existing single source of truth if available
    fn = globals().get("_vsp_guess_ci_run_dir_from_rid_v33")
    if callable(fn):
        try:
            d = fn(rid)
            if d and Path(d).exists():
                return str(Path(d))
        except Exception:
            pass

    # Fallback: common locations (keep minimal, commercial-safe)
    # - SECURITY-10-10-v4 out_ci format: /home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_YYYYmmdd_HHMMSS
    rid_norm = str(rid).strip()
    rid_norm = rid_norm.replace("RUN_", "").replace("VSP_UIREQ_", "VSP_CI_")
    # Try direct parse "VSP_CI_YYYYmmdd_HHMMSS"
    m = re.search(r"(VSP_CI_\d{8}_\d{6})", rid_norm)
    if m:
        cand = Path("/home/test/Data/SECURITY-10-10-v4/out_ci") / m.group(1)
        if cand.exists():
            return str(cand)

    # As last resort: try ui setting var if your app exports it
    base = globals().get("VSP_CI_OUT_BASE", None)
    if base:
        try:
            # pick newest match
            root = Path(base)
            if root.exists():
                items = sorted([x for x in root.glob("VSP_CI_*") if x.is_dir()], key=lambda x: x.stat().st_mtime, reverse=True)
                if items:
                    return str(items[0])
        except Exception:
            pass

    return None

def _vsp__inject_kics_summary_v2(ci_dir: str, payload: dict):
    payload.setdefault("kics_verdict", "")
    payload.setdefault("kics_total", 0)
    payload.setdefault("kics_counts", {})
    if not ci_dir:
        return
    ksum = _vsp__read_json_if_exists_v2(Path(ci_dir) / "kics" / "kics_summary.json")
    if isinstance(ksum, dict):
        payload["kics_verdict"] = str(ksum.get("verdict") or "")
        payload["kics_total"] = int(ksum.get("total") or 0)
        cnt = ksum.get("counts") or {}
        payload["kics_counts"] = cnt if isinstance(cnt, dict) else {}

def _vsp__inject_degraded_tools_v2(ci_dir: str, payload: dict):
    payload.setdefault("degraded_tools", [])
    if not ci_dir:
        return
    dj = _vsp__read_json_if_exists_v2(Path(ci_dir) / "degraded_tools.json")
    if isinstance(dj, list):
        payload["degraded_tools"] = dj

def _vsp__inject_stage_progress_v2(ci_dir: str, payload: dict):
    payload.setdefault("stage_name", "")
    payload.setdefault("stage_index", 0)
    payload.setdefault("stage_total", 0)
    payload.setdefault("progress_pct", 0)
    if not ci_dir:
        return
    # Prefer runner.log if exists
    tail = _vsp__tail_text_v2(Path(ci_dir) / "runner.log")
    if not tail:
        return
    m = None
    for mm in _STAGE_RE_V2.finditer(tail):
        m = mm
    if not m:
        return
    si = int(m.group(1) or 0)
    st = int(m.group(2) or 0)
    sn = (m.group(3) or "").strip()
    payload["stage_name"] = sn
    payload["stage_index"] = si
    payload["stage_total"] = st
    payload["progress_pct"] = int((si / st) * 100) if st > 0 else 0

def api_vsp_run_status_v2_winlast_v3(rid):
    payload = {
        "ok": True,
        "rid": str(rid),
        "ci_run_dir": None,
        "stage_name": "",
        "stage_index": 0,
        "stage_total": 0,
        "progress_pct": 0,
        "kics_verdict": "",
        "kics_total": 0,
        "kics_counts": {},
        "degraded_tools": [],
    }

    ci_dir = _vsp__resolve_ci_run_dir_v2(str(rid))
    payload["ci_run_dir"] = ci_dir

    if not ci_dir:
        payload["ok"] = False
        payload["error"] = "CI_RUN_DIR_NOT_FOUND"
        return jsonify(payload), 200

    _vsp__inject_stage_progress_v2(ci_dir, payload)
    _vsp__inject_degraded_tools_v2(ci_dir, payload)
    _vsp__inject_kics_summary_v2(ci_dir, payload)

    return jsonify(payload), 200

def _vsp__register_run_status_v2_winlast_v3():
    # Register on the *actual* app object that is serving.
    a = globals().get("app", None)
    if a is None:
        return
    try:
        a.add_url_rule(
            "/api/vsp/run_status_v2/<rid>",
            endpoint="api_vsp_run_status_v2_winlast_v3",
            view_func=api_vsp_run_status_v2_winlast_v3,
            methods=["GET"],
        )
    except Exception as e:
        # If endpoint already exists, ignore (idempotent for repeated imports)
        try:
            msg = str(e)
            if "existing endpoint function" in msg or "already exists" in msg:
                return
        except Exception:
            pass

# IMPORTANT: call register immediately at import-time (before first request)
_vsp__register_run_status_v2_winlast_v3()
# === END VSP_RUN_STATUS_V2_WINLAST_V3 ===
'''

# Insert right after: app = Flask(...)
m = re.search(r"(?m)^(?P<indent>\s*)app\s*=\s*Flask\s*\(.*?\)\s*$", t)
if not m:
    raise SystemExit("[ERR] cannot find 'app = Flask(...)' in vsp_demo_app.py (need manual anchor)")

insert_at = m.end()
t = t[:insert_at] + "\n" + BLOCK + "\n" + t[insert_at:]

p.write_text(t, encoding="utf-8")
print("[OK] inserted WINLAST_V3 right after app = Flask(...)")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart 8910 =="
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
curl -sS http://127.0.0.1:8910/healthz | jq . || true

echo "== VERIFY: route must respond 200 JSON (never 404) =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/FAKE_RID_SHOULD_NOT_404" | jq '{ok,error,ci_run_dir,http_code:(.http_code//null),kics_verdict,kics_total}'
