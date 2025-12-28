#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_afterreq_overall_${TS}"
echo "[BACKUP] ${F}.bak_afterreq_overall_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_OVERALL_AFTER_REQUEST_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(f"""
# {MARK}
# Robust: does not depend on where route is defined (app.route / bp.route / add_url_rule)
import json as _vsp_json

def _vsp_safe_int(v, default=0):
    try:
        return int(v) if v is not None else default
    except Exception:
        return default

def _vsp_infer_overall_from_counts(counts: dict, total: int = 0) -> str:
    counts = counts or {{}}
    c = _vsp_safe_int(counts.get("CRITICAL") or counts.get("critical"), 0)
    h = _vsp_safe_int(counts.get("HIGH") or counts.get("high"), 0)
    m = _vsp_safe_int(counts.get("MEDIUM") or counts.get("medium"), 0)
    l = _vsp_safe_int(counts.get("LOW") or counts.get("low"), 0)
    i = _vsp_safe_int(counts.get("INFO") or counts.get("info"), 0)
    t = _vsp_safe_int(counts.get("TRACE") or counts.get("trace"), 0)
    tot = _vsp_safe_int(total, 0)

    if c > 0 or h > 0: return "RED"
    if m > 0: return "AMBER"
    if tot > 0 or (l+i+t) > 0: return "GREEN"
    return "GREEN"

def _vsp_apply_overall_inference_on_payload(payload: dict):
    items = payload.get("items")
    if not isinstance(items, list):
        return payload
    for it in items:
        if not isinstance(it, dict):
            continue
        has_gate = bool(it.get("has_gate"))
        overall  = (it.get("overall") or "").strip().upper()
        counts   = it.get("counts") or {{}}
        total    = it.get("findings_total") or it.get("total") or 0

        inferred = _vsp_infer_overall_from_counts(counts, total)
        it["overall_inferred"] = inferred

        if has_gate and overall and overall != "UNKNOWN":
            it["overall_source"] = "gate"
        else:
            if (not overall) or overall == "UNKNOWN":
                it["overall"] = inferred
            it["overall_source"] = "inferred_counts"
    return payload

@app.after_request
def _vsp_p1_overall_after_request(resp):
    try:
        # only patch runs API
        if getattr(request, "path", "") != "/api/ui/runs_v3":
            return resp
        ct = (resp.headers.get("Content-Type") or "")
        if "application/json" not in ct:
            return resp
        raw = resp.get_data(as_text=True) or ""
        if not raw.strip():
            return resp
        obj = _vsp_json.loads(raw)
        if isinstance(obj, dict) and isinstance(obj.get("items"), list):
            obj = _vsp_apply_overall_inference_on_payload(obj)
            new_raw = _vsp_json.dumps(obj, ensure_ascii=False)
            resp.set_data(new_raw)
            resp.headers["Content-Length"] = str(len(new_raw.encode("utf-8")))
        return resp
    except Exception:
        return resp
""").rstrip() + "\n"

# insert before __main__ if present, else append EOF
m = re.search(r'(?ms)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s2 = s[:m.start()] + "\n\n" + block + "\n" + s[m.start():]
else:
    s2 = s + "\n\n" + block

p.write_text(s2, encoding="utf-8")
print("[OK] appended after_request overall patch")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^vsp-ui-8910\.service'; then
  sudo systemctl restart vsp-ui-8910.service
  echo "[OK] restarted vsp-ui-8910.service"
else
  rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
  [ -x bin/p1_ui_8910_single_owner_start_v2.sh ] && bin/p1_ui_8910_single_owner_start_v2.sh || true
  echo "[OK] restarted via single owner (if present)"
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify (print raw first 300 chars) =="
RAW="$(curl -sS "$BASE/api/ui/runs_v3?limit=3" | head -c 300 || true)"
echo "$RAW"
echo
echo "== verify parsed fields (no -f to avoid empty pipe) =="
curl -sS "$BASE/api/ui/runs_v3?limit=5" | python3 - <<'PY'
import sys, json
raw=sys.stdin.read()
try:
    d=json.loads(raw)
except Exception as e:
    print("[ERR] not json:", e)
    print(raw[:400])
    raise SystemExit(1)
for it in (d.get("items") or [])[:5]:
    print(it.get("rid"), "has_gate=",it.get("has_gate"),
          "overall=",it.get("overall"),
          "src=",it.get("overall_source"),
          "inf=",it.get("overall_inferred"))
PY
