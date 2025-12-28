#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import re, time

root = Path(".")
# exclude noisy dirs
EXCL = {"out_ci","out","bin",".venv",".git","node_modules"}

cands = []
for p in root.rglob("*.py"):
    if any(part in EXCL for part in p.parts):
        continue
    if ".bak_" in p.name:
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "/api/ui/runs_v3" in s:
        # score by how likely it's the handler
        score = 0
        score += 10 if re.search(r'@.*\.(route|get)\([^)]*/api/ui/runs_v3', s) else 0
        score += 5  if "jsonify" in s else 0
        score += 2  if "items" in s else 0
        cands.append((score, p, s))

if not cands:
    print("[ERR] cannot find any .py containing /api/ui/runs_v3")
    raise SystemExit(2)

cands.sort(key=lambda x: (-x[0], str(x[1])))
score, p, s = cands[0]
print(f"[OK] target={p} score={score}")

marker = "VSP_P1_FIX_OVERALL_RUNS_V3_V2"
if marker in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

bak = p.with_name(p.name + f".bak_fix_overall_runsv3_{time.strftime('%Y%m%d_%H%M%S')}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)

helper = f"""
# {marker}
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
""".rstrip() + "\n"

# Insert helper near top (after imports) to avoid decorator-time surprises
ins_at = 0
m = re.search(r'(?m)^(import |from )', s)
if m:
    # place after last import block
    imps = list(re.finditer(r'(?m)^(import |from ).*$', s))
    ins_at = imps[-1].end() if imps else 0

s2 = s[:ins_at] + "\n\n" + helper + "\n" + s[ins_at:]

# Patch the handler function block for runs_v3
rx = re.compile(r'(?ms)(@.*\.(?:route|get)\([^)]*/api/ui/runs_v3[^)]*\)\s*\n\s*def\s+\w+\([^\)]*\)\s*:\s*\n)(.*?)(?=^\s*@|\Z)')
m = rx.search(s2)
if not m:
    print("[ERR] found /api/ui/runs_v3 string but cannot locate decorator+def block")
    raise SystemExit(3)

head, body = m.group(1), m.group(2)

# inject before first "return jsonify(VAR)"
mret = re.search(r'(?m)^\s*return\s+jsonify\(\s*([A-Za-z_]\w*)\s*\)\s*$', body)
if not mret:
    # fallback: before first return
    rpos = re.search(r'(?m)^\s*return\s+', body)
    if not rpos:
        print("[ERR] cannot find return in runs_v3 handler")
        raise SystemExit(4)
    inj = """
    # VSP_P1_FIX_OVERALL_RUNS_V3_V2_HOOK
    try:
        _cand = locals().get("out") or locals().get("resp") or locals().get("data") or locals().get("result")
        if isinstance(_cand, dict):
            _vsp_apply_overall_inference_on_payload(_cand)
    except Exception:
        pass

"""
    body2 = body[:rpos.start()] + inj + body[rpos.start():]
else:
    var = mret.group(1)
    inj = f"""
    # VSP_P1_FIX_OVERALL_RUNS_V3_V2_HOOK
    try:
        _vsp_apply_overall_inference_on_payload({var})
    except Exception:
        pass
"""
    body2 = body[:mret.start()] + inj + body[mret.start():]

s3 = s2[:m.start()] + head + body2 + s2[m.end():]
p.write_text(s3, encoding="utf-8")
print("[OK] patched runs_v3 handler in", p)
PY

# compile sanity
python3 -m py_compile $(python3 - <<'PY'
from pathlib import Path
import sys
# compile all likely modules quickly
print("wsgi_vsp_ui_gateway.py")
PY
) && echo "[OK] py_compile OK" || true

# restart
sudo systemctl restart vsp-ui-8910.service || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify =="
ss -ltnp | egrep '(:8910)' || true
curl -sS "$BASE/api/ui/runs_v3?limit=3" | python3 - <<'PY'
import sys, json
raw=sys.stdin.read()
d=json.loads(raw)
for it in d.get("items",[])[:3]:
    print(it.get("rid"), it.get("has_gate"), it.get("overall"), it.get("overall_source"), it.get("overall_inferred"))
PY
