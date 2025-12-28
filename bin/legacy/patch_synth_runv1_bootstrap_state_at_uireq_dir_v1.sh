#!/usr/bin/env bash
set -euo pipefail

FILES=(
  "run_api/vsp_watchdog_v1.py"
  "run_api/vsp_run_api_v1.py"
)

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
import re
from pathlib import Path

MARK = "VSP_SYNTH_RUNV1_BOOTSTRAP_UIREQDIR_V1"

targets = [Path(p) for p in [
  "run_api/vsp_watchdog_v1.py",
  "run_api/vsp_run_api_v1.py",
] if Path(p).is_file()]

def add_helper(txt: str) -> str:
    if MARK in txt:
        return txt
    helper = f"""
# === {MARK} ===
def _vsp_write_uireq_state_v1(req_id: str, req_payload: dict):
  try:
    from pathlib import Path
    import json, time, os
    d = None
    try:
      d = globals().get("_VSP_UIREQ_DIR", None)
    except Exception:
      d = None
    if d:
      st_dir = Path(d)
    else:
      # fallback if _VSP_UIREQ_DIR missing (best effort)
      st_dir = Path(__file__).resolve().parents[1] / "ui" / "out_ci" / "uireq_v1"
    st_dir.mkdir(parents=True, exist_ok=True)
    st = st_dir / (str(req_id) + ".json")

    state0 = {{}}
    if st.is_file():
      try:
        state0 = json.loads(st.read_text(encoding="utf-8", errors="ignore") or "{{}}")
        if not isinstance(state0, dict):
          state0 = {{}}
      except Exception:
        state0 = {{}}

    state0.setdefault("request_id", str(req_id))
    state0.setdefault("synthetic_req_id", True)
    for k in ("mode","profile","target_type","target"):
      if (not state0.get(k)) and (req_payload.get(k) is not None):
        state0[k] = req_payload.get(k) or ""

    state0.setdefault("ci_run_dir", "")
    state0.setdefault("runner_log", "")
    state0.setdefault("ci_root_from_pid", None)
    state0.setdefault("watchdog_pid", 0)
    state0.setdefault("stage_sig", "0/0||0")
    state0.setdefault("progress_pct", 0)
    state0.setdefault("killed", False)
    state0.setdefault("kill_reason", "")
    state0.setdefault("final", False)

    state0.setdefault("stall_timeout_sec", int(os.environ.get("VSP_STALL_TIMEOUT_SEC","600")))
    state0.setdefault("total_timeout_sec", int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200")))
    state0["state_bootstrap_ts"] = int(time.time())

    st.write_text(json.dumps(state0, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[{MARK}] wrote {{st}}")
  except Exception as e:
    try:
      print(f"[{MARK}] FAILED:", e)
    except Exception:
      pass
# === END {MARK} ===
"""
    # insert helper after imports (best effort)
    m = re.search(r"(\n(?:from|import)\s+[^\n]+)+\n", txt, flags=re.M)
    if m:
        return txt[:m.end()] + helper + "\n" + txt[m.end():]
    return helper + "\n" + txt

def inject_after_synth_dict(txt: str) -> tuple[str,int]:
    # Find a dict literal containing "synthetic_req_id": True
    # We'll inject after the closing brace of that dict, inside the same indent scope.
    lines = txt.splitlines(True)
    n = 0
    i = 0
    while i < len(lines):
        if 'synthetic_req_id' in lines[i] and 'True' in lines[i]:
            # walk backward to find start of dict assignment line: something = {
            j = i
            while j >= 0 and '{' not in lines[j]:
                j -= 1
            if j < 0:
                i += 1
                continue
            # capture indent from that assignment line
            indent = re.match(r"^(\s*)", lines[j]).group(1)

            # walk forward to find matching closing brace for this dict literal (line that starts with indent + "}")
            k = i
            # naive: stop at first line that matches indent + "}"
            while k < len(lines) and not re.match(rf"^{re.escape(indent)}\}}\s*,?\s*$", lines[k]):
                k += 1
            if k >= len(lines):
                i += 1
                continue

            # inject just after closing brace line k
            inj = f"""{indent}# === {MARK} INJECT ===
{indent}try:
{indent}  _rid = None
{indent}  try:
{indent}    _req_payload = request.get_json(silent=True) or {{}}
{indent}  except Exception:
{indent}    _req_payload = {{}}
{indent}  # try common vars: out/res/payload + locals
{indent}  for _name in ("out","res","resp","payload","data","body"):
{indent}    v = locals().get(_name)
{indent}    if isinstance(v, dict) and v.get("request_id"):
{indent}      _rid = str(v.get("request_id"))
{indent}      break
{indent}  if not _rid:
{indent}    for _k in ("request_id","req_id","rid","REQ_ID"):
{indent}      if locals().get(_k):
{indent}        _rid = str(locals().get(_k))
{indent}        break
{indent}  if _rid:
{indent}    _vsp_write_uireq_state_v1(_rid, _req_payload)
{indent}except Exception:
{indent}  pass
{indent}# === END {MARK} INJECT ===
"""
            lines.insert(k+1, inj + "\n")
            n += 1
            # skip forward
            i = k + 2
            continue
        i += 1
    return "".join(lines), n

for fp in targets:
    orig = fp.read_text(encoding="utf-8", errors="ignore")
    txt = add_helper(orig)
    txt2, n = inject_after_synth_dict(txt)
    if n == 0:
        print("[WARN] no synthetic_req_id dict found in", fp)
        continue
    fp.write_text(txt2, encoding="utf-8")
    print("[OK] patched", fp, "inject_count=", n)
PY

for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    python3 -m py_compile "$f" || exit 1
  fi
done

echo "[OK] py_compile OK (patched where applicable)"
