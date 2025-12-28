#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
OUT_DIR="$UI_ROOT/out_ci/uireq_v1"
mkdir -p "$OUT_DIR"

mapfile -t FILES < <(grep -Rsl --include='*.py' '/api/vsp/run_status_v1' "$UI_ROOT" || true)
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[ERR] No python file contains '/api/vsp/run_status_v1' under $UI_ROOT"
  exit 2
fi

echo "[INFO] Found ${#FILES[@]} candidate(s):"
printf ' - %s\n' "${FILES[@]}"

for F in "${FILES[@]}"; do
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$F" "$F.bak_persist_uireq_route_v19_${TS}"
  echo "[BACKUP] $F.bak_persist_uireq_route_v19_${TS}"

  python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)
txt = "".join(lines)

if "VSP_UIREQ_PERSIST_ROUTE_V19" in txt:
    print(f"[SKIP] already patched: {p.name}")
    raise SystemExit(0)

HELPER = r'''
# === VSP_UIREQ_PERSIST_ROUTE_V19 ===
import os as _os
import json as _json
import time as _time
import traceback as _traceback

_VSP_UIREQ_DIR_V19 = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1"
_VSP_HIT_LOG_V19   = _VSP_UIREQ_DIR_V19 + "/_persist_hits.log"
_VSP_ERR_LOG_V19   = _VSP_UIREQ_DIR_V19 + "/_persist_err.log"

def _vsp_append_v19(path, line):
    try:
        _os.makedirs(_VSP_UIREQ_DIR_V19, exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(line.rstrip("\n") + "\n")
    except Exception:
        pass

def _vsp_uireq_update_v19(rid: str, payload: dict):
    fp = _VSP_UIREQ_DIR_V19 + f"/{rid}.json"
    try:
        _os.makedirs(_VSP_UIREQ_DIR_V19, exist_ok=True)
        try:
            cur = _json.loads(open(fp, "r", encoding="utf-8").read())
        except Exception:
            cur = {"ok": True, "req_id": rid}

        if not isinstance(payload, dict):
            payload = {}

        # commercial: don't overwrite good values with None/""
        for k, v in payload.items():
            if v is None:
                continue
            if k in ("ci_run_dir","runner_log","stage_sig") and v == "":
                continue
            cur[k] = v

        cur["req_id"] = cur.get("req_id") or rid
        cur["updated_at"] = _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime())

        tmp = fp + ".tmp"
        open(tmp, "w", encoding="utf-8").write(_json.dumps(cur, ensure_ascii=False, indent=2))
        _os.replace(tmp, fp)
        return True
    except Exception as e:
        _vsp_append_v19(_VSP_ERR_LOG_V19, f"update_fail rid={rid} err={repr(e)} file={__file__}")
        _vsp_append_v19(_VSP_ERR_LOG_V19, _traceback.format_exc())
        return False

def vsp_jsonify_persist_uireq_v19(payload):
    # HIT marker: prove handler/module is active
    try:
        rid0 = None
        if isinstance(payload, dict):
            rid0 = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
        _vsp_append_v19(_VSP_HIT_LOG_V19, f"hit ts={_time.time()} file={__file__} rid={rid0}")
    except Exception:
        pass

    try:
        if isinstance(payload, dict):
            rid = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
            if rid:
                _vsp_uireq_update_v19(str(rid), payload)
            else:
                _vsp_append_v19(_VSP_ERR_LOG_V19, f"missing_rid keys={list(payload.keys())} file={__file__}")
        else:
            _vsp_append_v19(_VSP_ERR_LOG_V19, f"payload_not_dict type={type(payload)} file={__file__}")
    except Exception as e:
        _vsp_append_v19(_VSP_ERR_LOG_V19, f"persist_exception err={repr(e)} file={__file__}")
        _vsp_append_v19(_VSP_ERR_LOG_V19, _traceback.format_exc())

    return jsonify(payload)
# === END VSP_UIREQ_PERSIST_ROUTE_V19 ===
'''.lstrip("\n")

# insert helper after imports (best-effort)
m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', txt, flags=re.M)
if m:
    txt = txt[:m.end()] + "\n" + HELPER + "\n" + txt[m.end():]
else:
    ls = txt.splitlines(True)
    txt = "".join(ls[:1]) + "\n" + HELPER + "\n" + "".join(ls[1:])

lines = txt.splitlines(True)

# find a line containing route
route_idx = None
for i, ln in enumerate(lines):
    if "/api/vsp/run_status_v1" in ln:
        route_idx = i
        break
if route_idx is None:
    print(f"[SKIP] route not found after insert: {p.name}")
    p.write_text("".join(lines), encoding="utf-8")
    raise SystemExit(0)

# find next def after that line
def_idx = None
for j in range(route_idx, min(route_idx + 250, len(lines))):
    if re.match(r'^\s*def\s+\w+\s*\(.*\)\s*:\s*$', lines[j]):
        def_idx = j
        break
if def_idx is None:
    print(f"[ERR] cannot find def after route line in {p.name}")
    raise SystemExit(3)

def_indent = len(lines[def_idx]) - len(lines[def_idx].lstrip(" \t"))

# find end of that function
end = len(lines)
for k in range(def_idx + 1, len(lines)):
    ln = lines[k]
    if ln.strip() == "":
        continue
    ind = len(ln) - len(ln.lstrip(" \t"))
    if ind <= def_indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@")):
        end = k
        break

# add an entry HIT at function start (literal string, no patch-time eval)
body_indent = re.match(r'^(\s*)', lines[def_idx+1]).group(1) if def_idx+1 < len(lines) else (" " * (def_indent + 2))
entry = body_indent + '_vsp_append_v19(_VSP_HIT_LOG_V19, f"enter ts={_time.time()} file={__file__} route=/api/vsp/run_status_v1")\n'
lines.insert(def_idx+1, entry)

# replace returns in this function: jsonify(...) or older wrappers -> v19 wrapper
patched = 0
rx = re.compile(r'^(\s*)return\s+(?:jsonify|vsp_jsonify_persist_uireq_v14|vsp_jsonify_persist_uireq_v17|vsp_jsonify_persist_uireq_v18)\s*\(')
for k in range(def_idx, end+1):
    if k >= len(lines): break
    if rx.match(lines[k]):
        lines[k] = re.sub(rx, r'\1return vsp_jsonify_persist_uireq_v19(', lines[k])
        patched += 1

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched {p.name}: returns_patched={patched} def_line={def_idx}")
PY

  python3 -m py_compile "$F" >/dev/null && echo "[OK] py_compile: $F" || { echo "[ERR] py_compile failed: $F"; exit 4; }
done

echo "[DONE] HARD restart 8910 then poll status. Logs:"
echo "  tail -n 80 $OUT_DIR/_persist_hits.log"
echo "  tail -n 80 $OUT_DIR/_persist_err.log"
