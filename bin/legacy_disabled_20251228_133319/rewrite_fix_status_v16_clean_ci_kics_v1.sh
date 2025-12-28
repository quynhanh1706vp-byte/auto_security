#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rewrite_fixstatus_clean_${TS}"
echo "[BACKUP] $F.bak_rewrite_fixstatus_clean_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

FUNC = "_vsp_fix_status_from_body_v16"
tag  = "# === VSP_FIX_STATUS_REWRITE_CLEAN_CI_KICS_V1 ==="

# locate def line
def_re = re.compile(r'^([ \t]*)def\s+' + re.escape(FUNC) + r'\s*\([^)]*\)\s*:\s*$')
i0=None; indent=""
for i,l in enumerate(lines):
    m=def_re.match(l)
    if m:
        i0=i; indent=m.group(1); break
if i0 is None:
    raise SystemExit(f"[ERR] cannot find def {FUNC}(...)")

# locate end of function (next top-level def with same indent)
i1=None
for j in range(i0+1, len(lines)):
    lj=lines[j]
    if re.match(r'^def\s+\w+\s*\(', lj) and indent=="":
        i1=j; break
    if indent!="" and re.match(r'^' + re.escape(indent) + r'def\s+\w+\s*\(', lj):
        i1=j; break
if i1 is None:
    i1=len(lines)

# build new function block (keep def line, replace body)
def_line = lines[i0]
body_indent = indent + "    "

new_block = def_line + f"""{body_indent}{tag}
{body_indent}try:
{body_indent}    import json as _json
{body_indent}    from pathlib import Path as _Path

{body_indent}    # Only touch JSON-like responses; if cannot parse -> return as-is.
{body_indent}    obj = None
{body_indent}    try:
{body_indent}        obj = resp.get_json(silent=True)
{body_indent}    except Exception:
{body_indent}        obj = None
{body_indent}    if not isinstance(obj, dict):
{body_indent}        try:
{body_indent}            raw = (resp.get_data(as_text=True) or "")
{body_indent}            raw_s = raw.lstrip()
{body_indent}            if raw_s.startswith("{{"):
{body_indent}                obj = _json.loads(raw)
{body_indent}        except Exception:
{body_indent}            obj = None
{body_indent}    if not isinstance(obj, dict):
{body_indent}        return resp

{body_indent}    # defaults (commercial contract)
{body_indent}    obj.setdefault("ci_run_dir", None)
{body_indent}    obj.setdefault("kics_verdict", "")
{body_indent}    obj.setdefault("kics_total", 0)
{body_indent}    obj.setdefault("kics_counts", {{}})

{body_indent}    # RID from request.path (v1/v2)
{body_indent}    rid = ""
{body_indent}    try:
{body_indent}        from flask import request as _req
{body_indent}        path = (_req.path or "")
{body_indent}        if path.startswith("/api/vsp/run_status_v2/") or path.startswith("/api/vsp/run_status_v1/"):
{body_indent}            rid = (path.rsplit("/", 1)[-1] or "").split("?", 1)[0].strip()
{body_indent}    except Exception:
{body_indent}        rid = ""

{body_indent}    rid_norm = rid[4:].strip() if rid.startswith("RUN_") else rid

{body_indent}    # Fill ci_run_dir if missing
{body_indent}    if (not (obj.get("ci_run_dir") or "").strip()) and rid_norm:
{body_indent}        try:
{body_indent}            ci = _vsp_guess_ci_run_dir_from_rid_v33(rid_norm)
{body_indent}            if ci:
{body_indent}                obj["ci_run_dir"] = str(ci)
{body_indent}        except Exception:
{body_indent}            pass

{body_indent}    # Inject KICS summary
{body_indent}    ci_dir = (obj.get("ci_run_dir") or "").strip()
{body_indent}    if ci_dir:
{body_indent}        ks = _Path(ci_dir) / "kics" / "kics_summary.json"
{body_indent}        if ks.is_file():
{body_indent}            try:
{body_indent}                jj = _json.loads(ks.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{body_indent}                if isinstance(jj, dict):
{body_indent}                    obj["kics_verdict"] = str(jj.get("verdict") or obj.get("kics_verdict") or "")
{body_indent}                    try:
{body_indent}                        obj["kics_total"] = int(jj.get("total") or obj.get("kics_total") or 0)
{body_indent}                    except Exception:
{body_indent}                        pass
{body_indent}                    cc = jj.get("counts")
{body_indent}                    if isinstance(cc, dict):
{body_indent}                        obj["kics_counts"] = cc
{body_indent}            except Exception:
{body_indent}                pass

{body_indent}    # Fix http_code if present
{body_indent}    try:
{body_indent}        hc = obj.get("http_code")
{body_indent}        if isinstance(hc, int) and 400 <= hc <= 599:
{body_indent}            resp.status_code = hc
{body_indent}    except Exception:
{body_indent}        pass

{body_indent}    # Write back JSON to response
{body_indent}    try:
{body_indent}        resp.set_data(_json.dumps(obj, ensure_ascii=False))
{body_indent}        resp.mimetype = "application/json"
{body_indent}    except Exception:
{body_indent}        pass
{body_indent}    return resp
{body_indent}except Exception:
{body_indent}    return resp
"""

out = lines[:i0] + [new_block] + lines[i1:]
p.write_text("".join(out), encoding="utf-8")
print(f"[OK] rewrote {FUNC} lines {i0+1}..{i1}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
