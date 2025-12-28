#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pick="$(grep -Rsl --include='*.py' '/api/vsp/run_v1' "$ROOT" | head -n 1 || true)"
[ -n "${pick:-}" ] || { echo "[ERR] cannot find any *.py containing /api/vsp/run_v1 under $ROOT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$pick" "$pick.bak_persist_uireq_v10_${TS}"
echo "[BACKUP] $pick.bak_persist_uireq_v10_${TS}"

python3 - "$pick" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

txt = "".join(lines)
if "VSP_UIREQ_PERSIST_V10" in txt:
    print("[OK] already patched (V10).")
    raise SystemExit(0)

# --- inject helper once (near top after imports best-effort) ---
helper = r'''
# === VSP_UIREQ_PERSIST_V10 ===
from pathlib import Path as _Path
import json as _json
import time as _time
import os as _os

def _uireq_state_dir_v10():
    base = _Path(__file__).resolve().parent
    d = base / "out_ci" / "uireq_v1"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _uireq_state_update_v10(req_id: str, patch: dict):
    try:
        fp = _uireq_state_dir_v10() / f"{req_id}.json"
        try:
            cur = _json.loads(fp.read_text(encoding="utf-8"))
        except Exception:
            cur = {"ok": True, "req_id": req_id}

        for k, v in (patch or {}).items():
            if v is None:
                continue
            cur[k] = v

        cur["req_id"] = cur.get("req_id") or req_id
        cur["updated_at"] = _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime())

        tmp = str(fp) + ".tmp"
        _Path(tmp).write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
        _os.replace(tmp, fp)
        return True
    except Exception:
        try:
            app.logger.exception("[UIREQ][V10] persist update failed")
        except Exception:
            pass
        return False
# === END VSP_UIREQ_PERSIST_V10 ===
'''.lstrip("\n")

# insert helper after first import block
joined = "".join(lines)
m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', joined, flags=re.M)
if m:
    insert_pos = m.end()
    joined = joined[:insert_pos] + "\n" + helper + "\n" + joined[insert_pos:]
    lines = joined.splitlines(True)
else:
    # fallback: after shebang or first line
    if lines and lines[0].startswith("#!"):
        lines.insert(1, "\n" + helper + "\n")
    else:
        lines.insert(0, helper + "\n")

# --- locate the function handling /api/vsp/run_v1 and inject hook before returns ---
# find route line index
idx_route = None
for i, ln in enumerate(lines):
    if "/api/vsp/run_v1" in ln:
        idx_route = i
        break
if idx_route is None:
    print("[ERR] route string disappeared after helper insert; abort.")
    raise SystemExit(3)

# find next def line after route
idx_def = None
for j in range(idx_route, min(idx_route + 120, len(lines))):
    if re.match(r'^\s*def\s+\w+\s*\(.*\)\s*:\s*$', lines[j]):
        idx_def = j
        break
if idx_def is None:
    print("[ERR] cannot find def ...(): after route decorator.")
    raise SystemExit(4)

def_indent = len(lines[idx_def]) - len(lines[idx_def].lstrip(" \t"))
# function block end: next top-level def/@ with indent <= def_indent
end = len(lines)
for k in range(idx_def + 1, len(lines)):
    ln = lines[k]
    if ln.strip() == "":
        continue
    ind = len(ln) - len(ln.lstrip(" \t"))
    if ind <= def_indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@")):
        end = k
        break

hook_tpl = r'''
{indent}# === VSP_UIREQ_PERSIST_V10 hook (run_v1) ===
{indent}try:
{indent}    _rid = locals().get("req_id") or locals().get("request_id")
{indent}    if _rid:
{indent}        _uireq_state_update_v10(
{indent}            _rid,
{indent}            {{
{indent}              "ci_run_dir": locals().get("ci_run_dir"),
{indent}              "runner_log": locals().get("runner_log"),
{indent}              "status": locals().get("status"),
{indent}              "final": locals().get("final"),
{indent}              "error": locals().get("error"),
{indent}            }},
{indent}        )
{indent}except Exception:
{indent}    pass
{indent}# === END VSP_UIREQ_PERSIST_V10 hook (run_v1) ===
'''.lstrip("\n")

# inject hook before every "return jsonify" within [idx_def, end)
out = []
i = 0
while i < len(lines):
    if idx_def <= i < end and re.match(r'^\s*return\s+jsonify\s*\(', lines[i]):
        indent = re.match(r'^(\s*)', lines[i]).group(1)
        out.append(hook_tpl.format(indent=indent))
    out.append(lines[i])
    i += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] patched {p.name}: injected persist hook before return jsonify in run_v1.")
PY

echo "== PY COMPILE CHECK =="
python3 -m py_compile "$pick" && echo "[OK] py_compile passed"

echo "== QUICK GREP (V10) =="
grep -n "VSP_UIREQ_PERSIST_V10" "$pick" | head -n 80 || true

echo "[DONE] Restart 8910, then POST /api/vsp/run_v1 and check ui/out_ci/uireq_v1/<RID>.json"
