#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
OUT_DIR="$UI_ROOT/out_ci/uireq_v1"
mkdir -p "$OUT_DIR"

mapfile -t FILES < <(grep -Rsl --include='*.py' -E '^\s*def\s+run_status_v1\s*\(' "$UI_ROOT" || true)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[ERR] No python file with 'def run_status_v1(' found under $UI_ROOT"
  exit 2
fi

echo "[INFO] Found ${#FILES[@]} file(s):"
printf ' - %s\n' "${FILES[@]}"

for F in "${FILES[@]}"; do
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$F" "$F.bak_persist_uireq_v17_${TS}"
  echo "[BACKUP] $F.bak_persist_uireq_v17_${TS}"

  python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_UIREQ_PERSIST_MULTI_V17" in txt:
    print(f"[SKIP] already patched: {p.name}")
    raise SystemExit(0)

HELPER = r'''
# === VSP_UIREQ_PERSIST_MULTI_V17 ===
import os as _os
import json as _json
import time as _time
import traceback as _traceback

_VSP_UIREQ_DIR_V17 = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1"
_VSP_HIT_LOG_V17   = _VSP_UIREQ_DIR_V17 + "/_persist_hits.log"
_VSP_ERR_LOG_V17   = _VSP_UIREQ_DIR_V17 + "/_persist_err.log"

def _vsp_append_v17(path, line):
    try:
        _os.makedirs(_VSP_UIREQ_DIR_V17, exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(line.rstrip("\n") + "\n")
    except Exception:
        pass

def _vsp_uireq_update_v17(rid: str, payload: dict):
    try:
        _os.makedirs(_VSP_UIREQ_DIR_V17, exist_ok=True)
        fp = _VSP_UIREQ_DIR_V17 + f"/{rid}.json"
        try:
            cur = _json.loads(open(fp, "r", encoding="utf-8").read())
        except Exception:
            cur = {"ok": True, "req_id": rid}

        if not isinstance(payload, dict):
            payload = {}

        # commercial rule: don't overwrite good values with None/""
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
        _vsp_append_v17(_VSP_ERR_LOG_V17, f"update_fail rid={rid} err={repr(e)} file={__file__}")
        _vsp_append_v17(_VSP_ERR_LOG_V17, _traceback.format_exc())
        return False

def vsp_jsonify_persist_uireq_v17(payload):
    # HIT marker (prove handler/module is active)
    try:
        rid0 = None
        if isinstance(payload, dict):
            rid0 = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
        _vsp_append_v17(_VSP_HIT_LOG_V17, f"hit ts={_time.time()} file={__file__} rid={rid0}")
    except Exception:
        pass

    try:
        if isinstance(payload, dict):
            rid = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
            if rid:
                _vsp_uireq_update_v17(str(rid), payload)
            else:
                _vsp_append_v17(_VSP_ERR_LOG_V17, f"missing_rid payload_keys={list(payload.keys())} file={__file__}")
        else:
            _vsp_append_v17(_VSP_ERR_LOG_V17, f"payload_not_dict type={type(payload)} file={__file__}")
    except Exception as e:
        _vsp_append_v17(_VSP_ERR_LOG_V17, f"persist_exception err={repr(e)} file={__file__}")
        _vsp_append_v17(_VSP_ERR_LOG_V17, _traceback.format_exc())

    return jsonify(payload)
# === END VSP_UIREQ_PERSIST_MULTI_V17 ===
'''.lstrip("\n")

# Insert helper after import block (best-effort)
m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', txt, flags=re.M)
if m:
    txt = txt[:m.end()] + "\n" + HELPER + "\n" + txt[m.end():]
else:
    lines0 = txt.splitlines(True)
    txt = "".join(lines0[:1]) + "\n" + HELPER + "\n" + "".join(lines0[1:])

# Locate run_status_v1 function block
mm = re.search(r'^\s*def\s+run_status_v1\s*\(.*\)\s*:\s*$', txt, flags=re.M)
if not mm:
    print(f"[SKIP] no def run_status_v1 in {p.name}")
    p.write_text(txt, encoding="utf-8")
    raise SystemExit(0)

def_start = mm.start()
def_indent = len(mm.group(0)) - len(mm.group(0).lstrip(" \t"))

lines = txt.splitlines(True)
pos = 0
li_def = 0
for i, ln in enumerate(lines):
    if pos <= def_start < pos + len(ln):
        li_def = i
        break
    pos += len(ln)

end = len(lines)
for j in range(li_def + 1, len(lines)):
    ln = lines[j]
    if ln.strip() == "":
        continue
    ind = len(ln) - len(ln.lstrip(" \t"))
    if ind <= def_indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@")):
        end = j
        break

# Replace return jsonify(...) inside run_status_v1
for k in range(li_def, end):
    lines[k] = re.sub(r'^(\s*)return\s+jsonify\s*\(', r'\1return vsp_jsonify_persist_uireq_v17(', lines[k])

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched: {p.name}")
PY

  python3 -m py_compile "$F" >/dev/null && echo "[OK] py_compile: $F" || { echo "[ERR] py_compile failed: $F"; exit 3; }
done

echo "[DONE] Restart 8910, then poll run_status. Check:"
echo "  tail -n 50 $OUT_DIR/_persist_hits.log"
echo "  tail -n 80 $OUT_DIR/_persist_err.log"
