#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [A] restore from latest bak_kics_summary =="
BAK="$(ls -1t vsp_demo_app.py.bak_kics_summary_* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] no backup found: vsp_demo_app.py.bak_kics_summary_*"; exit 2; }
cp -f "$BAK" "$F"
echo "[OK] restored: $BAK -> $F"

echo "== [B] apply kics_summary injection (safe indent) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")
TAG = "# === VSP_STATUS_INJECT_KICS_SUMMARY_V1 ==="

# 1) ensure helper exists (top-level, safe)
if "_vsp_read_kics_summary" not in t:
    helper = f'''
{TAG}
def _vsp_read_kics_summary(ci_run_dir: str):
    try:
        from pathlib import Path as _P
        fp = _P(ci_run_dir) / "kics" / "kics_summary.json"
        if not fp.exists():
            return None
        import json as _json
        obj = _json.loads(fp.read_text(encoding="utf-8", errors="ignore") or "{{}}")
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None
# === END VSP_STATUS_INJECT_KICS_SUMMARY_V1 ===

'''
    # insert after imports if possible; else prepend
    m = re.search(r'(^import .+\n|^from .+ import .+\n)+', t, flags=re.M)
    if m:
        ins = m.end()
        t = t[:ins] + "\n" + helper + t[ins:]
    else:
        t = helper + t

# 2) find a REAL code line that assigns kics_tail (not in strings)
lines = t.splitlines(True)
candidates = []
pat = re.compile(r'^\s*payload\[\s*[\'"]kics_tail[\'"]\s*\]\s*=')
for i, ln in enumerate(lines):
    if pat.search(ln) and ("run_status" in "".join(lines[max(0,i-80):i+80])):
        candidates.append(i)
if not candidates:
    # fallback: any payload["kics_tail"]= line
    for i, ln in enumerate(lines):
        if pat.search(ln):
            candidates.append(i)
            break
if not candidates:
    raise SystemExit("[ERR] cannot find payload['kics_tail']= anchor in code")

i = candidates[0]
indent = re.match(r'^(\s*)', lines[i]).group(1)

# ensure we're inside a function (look back for def at indent 0)
inside = False
for k in range(i, max(-1, i-400), -1):
    if re.match(r'^def\s+\w+\s*\(', lines[k]):
        inside = True
        break
    if re.match(r'^\S', lines[k]) and lines[k].lstrip().startswith("return "):
        # noisy, ignore
        pass
if not inside:
    raise SystemExit("[ERR] anchor not inside a function; abort to avoid breaking file")

addon = (
    f"{indent}{TAG}\n"
    f"{indent}try:\n"
    f"{indent}    ci_dir = payload.get('ci_run_dir') or payload.get('ci_run_dir_abs') or ''\n"
    f"{indent}    ks = _vsp_read_kics_summary(ci_dir) if ci_dir else None\n"
    f"{indent}    if isinstance(ks, dict):\n"
    f"{indent}        payload['kics_verdict'] = ks.get('verdict','') or ''\n"
    f"{indent}        payload['kics_counts']  = ks.get('counts',{{}}) if isinstance(ks.get('counts'), dict) else {{}}\n"
    f"{indent}        payload['kics_total']   = int(ks.get('total',0) or 0)\n"
    f"{indent}    else:\n"
    f"{indent}        payload.setdefault('kics_verdict','')\n"
    f"{indent}        payload.setdefault('kics_counts',{{}})\n"
    f"{indent}        payload.setdefault('kics_total',0)\n"
    f"{indent}except Exception:\n"
    f"{indent}    payload.setdefault('kics_verdict','')\n"
    f"{indent}    payload.setdefault('kics_counts',{{}})\n"
    f"{indent}    payload.setdefault('kics_total',0)\n"
    f"{indent}# === END VSP_STATUS_INJECT_KICS_SUMMARY_V1 ===\n"
)

# avoid duplicate insertion
if TAG in "".join(lines[i+1:i+80]):
    print("[OK] kics_summary injection already near anchor; skip")
else:
    lines.insert(i+1, addon)
    t2 = "".join(lines)
    p.write_text(t2, encoding="utf-8")
    print(f"[OK] injected after kics_tail at line ~{i+1}, indent={len(indent)}")
PY

echo "== [C] py_compile =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [D] restart service =="
if command -v systemctl >/dev/null 2>&1 && systemctl list-units --full -all | grep -q '^vsp-ui-gateway\.service'; then
  sudo systemctl restart vsp-ui-gateway
  sudo systemctl is-active vsp-ui-gateway && echo "[OK] vsp-ui-gateway active"
else
  /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
fi

echo "== [E] quick verify =="
curl -sS http://127.0.0.1:8910/healthz | jq . || true
