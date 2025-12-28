#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_overall_unknown_${TS}"
echo "[BACKUP] ${F}.bak_fix_overall_unknown_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_FIX_RUNS_OVERALL_UNKNOWN_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

helper = textwrap.dedent(f"""
# {MARK}
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
    try:
        items = payload.get("items")
        if not isinstance(items, list): return
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
    except Exception:
        return
""").rstrip() + "\n"

# insert helper before __main__ or append EOF
m = re.search(r'(?ms)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s = s[:m.start()] + "\n\n" + helper + "\n" + s[m.start():]
else:
    s = s + "\n\n" + helper

# patch /api/ui/runs_v3: look for 'return jsonify(out)' OR 'return jsonify(resp)' etc.
def patch_runs_route(src: str) -> str:
    route = "/api/ui/runs_v3"
    m = re.search(r'(?ms)(@app\.route\([^\)]*' + re.escape(route) + r'[^\)]*\)\s*\n\s*def\s+\w+\([^\)]*\)\s*:\s*\n)(.*?)(?=^\s*@app\.route|\Z)', src)
    if not m:
        print("[WARN] cannot find runs_v3 route block")
        return src
    head, body = m.group(1), m.group(2)
    if "VSP_P1_INFER_OVERALL_IN_RUNS_V3" in body:
        return src

    # Try inject just before 'return jsonify(X)'
    replaced = False
    for var in ("out","resp","data","result","payload"):
        pat = re.compile(r'(?m)^\s*return\s+jsonify\(\s*' + var + r'\s*\)\s*$')
        if pat.search(body):
            body = pat.sub(textwrap.dedent(f"""\
                # VSP_P1_INFER_OVERALL_IN_RUNS_V3
                try:
                    _vsp_apply_overall_inference_on_payload({var})
                except Exception:
                    pass
                return jsonify({var})
            """).rstrip(), body, count=1)
            replaced = True
            break

    if not replaced:
        # last resort: if 'return jsonify(' exists, inject generic hook before first return
        rpos = re.search(r'(?m)^\s*return\s+', body)
        if rpos:
            body = body[:rpos.start()] + textwrap.dedent("""\
                # VSP_P1_INFER_OVERALL_IN_RUNS_V3
                try:
                    _cand = locals().get("out") or locals().get("resp") or locals().get("data") or locals().get("result")
                    if isinstance(_cand, dict):
                        _vsp_apply_overall_inference_on_payload(_cand)
                except Exception:
                    pass

            """) + body[rpos.start():]
            replaced = True

    if not replaced:
        print("[WARN] runs_v3: no return found to hook")
        return src

    return src[:m.start()] + head + body + src[m.end():]

s2 = patch_runs_route(s)
p.write_text(s2, encoding="utf-8")
print("[OK] patched runs_v3 overall inference")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^vsp-ui-8910\.service'; then
  sudo systemctl restart vsp-ui-8910.service
else
  rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
  [ -x bin/p1_ui_8910_single_owner_start_v2.sh ] && bin/p1_ui_8910_single_owner_start_v2.sh || true
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify overall field (should not be UNKNOWN for no-gate runs) =="
curl -fsS "$BASE/api/ui/runs_v3?limit=5" | python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
for it in d.get("items",[])[:5]:
    print(it.get("rid"), "has_gate=",it.get("has_gate"),
          "overall=",it.get("overall"),
          "src=",it.get("overall_source"),
          "inf=",it.get("overall_inferred"))
PY
