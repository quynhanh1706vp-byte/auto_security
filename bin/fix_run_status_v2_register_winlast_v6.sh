#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_pre_runstatusv2_v6_${TS}"
echo "[BACKUP] $F.bak_pre_runstatusv2_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, io, tokenize

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# ---- 0) Remove any older injected blocks + stray register calls (including broken V5) ----
remove_pats = [
    r"\n# === VSP_ADD_RUN_STATUS_V2_FALLBACK_V1 ===.*?# === END VSP_ADD_RUN_STATUS_V2_FALLBACK_V1 ===\n",
    r"\n# === VSP_ADD_RUN_STATUS_V2_FALLBACK_WINLAST_V2 ===.*?# === END VSP_ADD_RUN_STATUS_V2_FALLBACK_WINLAST_V2 ===\n",
    r"\n# === VSP_RUN_STATUS_V2_WINLAST_V3 ===.*?# === END VSP_RUN_STATUS_V2_WINLAST_V3 ===\n",
    r"\n# === VSP_RUN_STATUS_V2_WINLAST_V4 ===.*?# === END VSP_RUN_STATUS_V2_WINLAST_V4 ===\n",
    r"\n# === VSP_RUN_STATUS_V2_WINLAST_V5 ===.*?# === END VSP_RUN_STATUS_V2_WINLAST_V5 ===\n",
    r"\n# === VSP_RUN_STATUS_V2_WINLAST_V6 ===.*?# === END VSP_RUN_STATUS_V2_WINLAST_V6 ===\n",
]
for pat in remove_pats:
    t = re.sub(pat, "\n", t, flags=re.S)

# remove old register call lines if present
t = re.sub(r"(?m)^\s*_vsp__register_run_status_v2_winlast_v[3456]\(app\)\s*$\n?", "", t)

TAG = "# === VSP_RUN_STATUS_V2_WINLAST_V6 ==="
END = "# === END VSP_RUN_STATUS_V2_WINLAST_V6 ==="

BLOCK = r'''
# === VSP_RUN_STATUS_V2_WINLAST_V6 ===
# Commercial harden: /api/vsp/run_status_v2/<rid> never 404, inject stage + degraded + KICS summary.
import json, re
from pathlib import Path
from flask import jsonify

_STAGE_RE_V2 = re.compile(r"=+\s*\[\s*(\d+)\s*/\s*(\d+)\s*\]\s*([^\]]+?)\s*\]+", re.IGNORECASE)

def _vsp__read_json_if_exists_v2(pp: Path):
    try:
        if pp and pp.exists() and pp.is_file():
            return json.loads(pp.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None
    return None

def _vsp__tail_text_v2(pp: Path, max_bytes: int = 20000) -> str:
    try:
        if not pp.exists() or not pp.is_file():
            return ""
        bs = pp.read_bytes()
        if len(bs) > max_bytes:
            bs = bs[-max_bytes:]
        return bs.decode("utf-8", errors="ignore")
    except Exception:
        return ""

def _vsp__resolve_ci_run_dir_v2(rid: str):
    fn = globals().get("_vsp_guess_ci_run_dir_from_rid_v33")
    if callable(fn):
        try:
            d = fn(rid)
            if d and Path(d).exists():
                return str(Path(d))
        except Exception:
            pass

    rid_norm = str(rid).strip()
    rid_norm = rid_norm.replace("RUN_", "").replace("VSP_UIREQ_", "VSP_CI_")
    m = re.search(r"(VSP_CI_\d{8}_\d{6})", rid_norm)
    if m:
        cand = Path("/home/test/Data/SECURITY-10-10-v4/out_ci") / m.group(1)
        if cand.exists():
            return str(cand)
    return None

def _vsp__inject_stage_progress_v2(ci_dir: str, payload: dict):
    payload.setdefault("stage_name", "")
    payload.setdefault("stage_index", 0)
    payload.setdefault("stage_total", 0)
    payload.setdefault("progress_pct", 0)
    if not ci_dir:
        return
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

def _vsp__inject_degraded_tools_v2(ci_dir: str, payload: dict):
    payload.setdefault("degraded_tools", [])
    if not ci_dir:
        return
    dj = _vsp__read_json_if_exists_v2(Path(ci_dir) / "degraded_tools.json")
    if isinstance(dj, list):
        payload["degraded_tools"] = dj

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

def api_vsp_run_status_v2_winlast_v6(rid):
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

def _vsp__register_run_status_v2_winlast_v6(flask_app):
    if flask_app is None:
        return
    try:
        flask_app.add_url_rule(
            "/api/vsp/run_status_v2/<rid>",
            endpoint="api_vsp_run_status_v2_winlast_v6",
            view_func=api_vsp_run_status_v2_winlast_v6,
            methods=["GET"],
        )
    except Exception as e:
        msg = str(e)
        if "already exists" in msg or "existing endpoint function" in msg:
            return
# === END VSP_RUN_STATUS_V2_WINLAST_V6 ===
'''

# ---- 1) Find the *end of the statement* that assigns global app (tokenize, safe for multiline) ----
lines = t.splitlines(True)

def abs_offset(line_no_1based: int, col: int) -> int:
    return sum(len(lines[i]) for i in range(line_no_1based-1)) + col

indent_level = 0
paren_depth = 0
saw_app_name = False
found_assign = False
assign_end = None  # (line, col) after NEWLINE

g = tokenize.generate_tokens(io.StringIO(t).readline)
for tok in g:
    tt = tok.type
    ts = tok.string

    if tt == tokenize.INDENT:
        indent_level += 1
        continue
    if tt == tokenize.DEDENT:
        indent_level = max(0, indent_level-1)
        continue

    if tt == tokenize.OP and ts in "([{":
        paren_depth += 1
    elif tt == tokenize.OP and ts in ")]}":
        paren_depth = max(0, paren_depth-1)

    if not found_assign:
        if indent_level == 0 and tt == tokenize.NAME and ts == "app" and tok.start[1] == 0:
            saw_app_name = True
            continue
        if saw_app_name:
            # skip whitespace/comments/newlines handled by tokenize; just look for '='
            if tt == tokenize.OP and ts == "=":
                found_assign = True
                saw_app_name = False
                continue
            # if something else breaks the pattern, reset
            if tt not in (tokenize.NL, tokenize.NEWLINE, tokenize.COMMENT):
                saw_app_name = False
            continue
    else:
        # we are inside the app assignment statement; end when NEWLINE at depth 0
        if tt == tokenize.NEWLINE and paren_depth == 0:
            assign_end = tok.end  # (line, col)
            break

if assign_end is None:
    # fallback: import app line at top-level (still safe)
    m = re.search(r"(?m)^\s*from\s+[A-Za-z0-9_\.]+\s+import\s+.*\bapp\b[^\n]*$", t)
    if not m:
        raise SystemExit("[ERR] cannot locate global `app` assignment or import in vsp_demo_app.py")
    insert_at = m.end()
    t2 = t[:insert_at] + "\n" + BLOCK + "\n" + "_vsp__register_run_status_v2_winlast_v6(app)\n" + t[insert_at:]
    p.write_text(t2, encoding="utf-8")
    print("[OK] inserted WINLAST_V6 after 'from ... import ... app ...' (fallback)")
    raise SystemExit(0)

# Insert after the NEWLINE that ends the app assignment statement
insert_at = abs_offset(assign_end[0], assign_end[1])
t2 = t[:insert_at] + "\n" + BLOCK + "\n" + "_vsp__register_run_status_v2_winlast_v6(app)\n" + t[insert_at:]

p.write_text(t2, encoding="utf-8")
print("[OK] inserted WINLAST_V6 after end-of-statement for global 'app = ...' and registered")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart 8910 =="
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
curl -sS http://127.0.0.1:8910/healthz | jq . || true

echo "== VERIFY: must NOT 404 (fake rid => CI_RUN_DIR_NOT_FOUND) =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/FAKE_RID_SHOULD_NOT_404" | jq '{ok,error,ci_run_dir,stage_name,progress_pct,kics_verdict,kics_total}'
