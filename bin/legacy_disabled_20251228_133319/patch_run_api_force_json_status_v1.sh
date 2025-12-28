#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_force_json_${TS}"
echo "[BACKUP] $PYF.bak_force_json_${TS}"

python3 - << 'PY'
import re, json
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

marker = "VSP_FORCE_JSON_STATUS_V1"
if marker not in txt:
    helper = r'''

# === VSP_FORCE_JSON_STATUS_V1 (do not edit manually) ===
import os, re, json, time, subprocess
from pathlib import Path

_STAGE_RE = re.compile(r"^\s*=+\s*\[(\d+)\s*/\s*(\d+)\]\s*(.*?)\s*=+\s*$")

def _ui_root():
    return Path(__file__).resolve().parents[1]  # .../SECURITY_BUNDLE/ui

def _bundle_root():
    return _ui_root().parent

def _uireq_dir():
    d = _ui_root() / "out_ci" / "uireq_v1"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _state_path(req_id: str) -> Path:
    return _uireq_dir() / f"{req_id}.json"

def _read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}

def _write_json(path: Path, obj: dict) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")

def _tail_file(path: Path, max_lines: int = 200) -> str:
    if not path or not path.exists():
        return ""
    try:
        data = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        return "\n".join(data[-max_lines:])
    except Exception:
        return ""

def _infer_ci_run_dir_from_target(state: dict) -> str:
    target = (state.get("meta") or {}).get("target") or ""
    if not target:
        return ""
    base = Path(target) / "out_ci"
    if not base.is_dir():
        return ""
    # pick latest VSP_CI_* dir
    cands = sorted(base.glob("VSP_CI_*"), key=lambda x: x.stat().st_mtime, reverse=True)
    return str(cands[0]) if cands else ""

def _parse_stage_from_tail(tail: str):
    if not tail:
        return None
    last = None
    for line in tail.splitlines():
        m = _STAGE_RE.match(line.strip())
        if m:
            i = int(m.group(1)); n = int(m.group(2)); name = (m.group(3) or "").strip()
            last = (i, n, name)
    return last

def _finalize_unify_sync(ci_run_dir: str) -> (bool, str):
    if not ci_run_dir:
        return False, "missing_ci_run_dir"
    run_dir = Path(ci_run_dir)
    if not run_dir.exists():
        return False, f"ci_run_dir_not_found:{ci_run_dir}"

    root = _bundle_root()
    unify = root / "bin" / "vsp_unify_from_run_dir_v1.sh"
    sync  = root / "bin" / "vsp_ci_sync_to_vsp_v1.sh"

    logs = []
    ok = True

    if unify.exists():
        r = subprocess.run([str(unify), str(run_dir)], capture_output=True, text=True)
        logs.append(f"[UNIFY rc={r.returncode}]")
        if r.returncode != 0:
            ok = False
            logs.append((r.stdout or "")[-2000:])
            logs.append((r.stderr or "")[-2000:])
    else:
        ok = False
        logs.append("[UNIFY missing]")

    if sync.exists():
        r2 = subprocess.run([str(sync), str(run_dir)], capture_output=True, text=True)
        logs.append(f"[SYNC rc={r2.returncode}]")
        if r2.returncode != 0:
            ok = False
            logs.append((r2.stdout or "")[-2000:])
            logs.append((r2.stderr or "")[-2000:])
    else:
        ok = False
        logs.append("[SYNC missing]")

    return ok, "\n".join([x for x in logs if x])

# === END VSP_FORCE_JSON_STATUS_V1 ===
'''
    txt = txt.rstrip() + "\n" + helper + "\n"

# Replace run_status_v1() function body completely (best-effort)
m = re.search(r"\ndef\s+run_status_v1\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*:\n", txt)
if not m:
    print("[ERR] cannot find def run_status_v1(req_id):")
    raise SystemExit(2)

param = m.group(1)
start = m.start() + 1
# find next top-level def
m2 = re.search(r"\n(?=def\s+[A-Za-z_][A-Za-z0-9_]*\s*\()", txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)
old = txt[start:end]

new_func = f"""def run_status_v1({param}):
  # commercial: ALWAYS return JSON (no text prefix)
  try:
    req_id = {param}
    sp = _state_path(req_id)
    if not sp.exists():
      return jsonify({{"ok": False, "req_id": req_id, "error": "not_found"}}), 404

    st = _read_json(sp)
    st.setdefault("ok", True)
    st["req_id"] = req_id

    # update tail from log_file
    log_file = st.get("log_file") or str((_uireq_dir() / f"{{req_id}}.log"))
    st["log_file"] = log_file
    tail = _tail_file(Path(log_file), 250)
    st["tail"] = tail

    # infer ci_run_dir if empty
    if not st.get("ci_run_dir"):
      st["ci_run_dir"] = _infer_ci_run_dir_from_target(st) or ""

    # parse stage/progress from tail
    stage = st.get("stage") or {{}}
    stage.setdefault("i", 0); stage.setdefault("n", 8); stage.setdefault("name", ""); stage.setdefault("progress", 0)
    parsed = _parse_stage_from_tail(tail)
    if parsed:
      i, n, name = parsed
      stage["i"] = i
      stage["n"] = n
      stage["name"] = name
      stage["progress"] = int(round((i / n) * 100)) if n else 0
    st["stage"] = stage

    # expose aliases expected by UI/widgets
    st["stage_index"] = int(stage.get("i", 0) or 0)
    st["stage_total"] = int(stage.get("n", 0) or 0)
    st["stage_name"] = str(stage.get("name", "") or "")
    st["progress_pct"] = int(stage.get("progress", 0) or 0)

    # finalize unify+sync when final==true
    if bool(st.get("final")) and st.get("ci_run_dir"):
      sync = st.get("sync") or {{}}
      if not bool(sync.get("done")):
        ok, msg = _finalize_unify_sync(st["ci_run_dir"])
        sync["done"] = True
        sync["ok"] = bool(ok)
        sync["msg"] = msg
      st["sync"] = sync

    _write_json(sp, st)
    return jsonify(st)
  except Exception as e:
    return jsonify({{"ok": False, "req_id": {param}, "error": str(e)}}), 500
"""

# splice
txt = txt[:start] + new_func + "\n" + txt[end:]
p.write_text(txt, encoding="utf-8")
print("[OK] replaced run_status_v1 with JSON-safe version")
PY

python3 -m py_compile "$PYF"
echo "[OK] py_compile OK"
echo "[DONE]"
