#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_map_ci_v2_${TS}"
echo "[BACKUP] $F.bak_map_ci_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_STATUS_MAP_CI_DIR_V2_DEBUG_SAFE"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# locate run_status_v1 block
m = re.search(r"(?m)^def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt)
if not m:
    print("[ERR] cannot find def run_status_v1(req_id):")
    raise SystemExit(2)

start = m.start()
# find the first "return jsonify(st" AFTER start (inside this function)
mret = re.search(r"(?m)^\s*return\s+jsonify\s*\(\s*st\s*\)\s*$", txt[m.end():])
if not mret:
    # fallback: allow "return jsonify(st)," variant
    mret = re.search(r"(?m)^\s*return\s+jsonify\s*\(\s*st\s*\)\s*,\s*\d+\s*$", txt[m.end():])
if not mret:
    print("[ERR] cannot find return jsonify(st) inside run_status_v1")
    raise SystemExit(3)

insert_pos = m.end() + mret.start()

block = r'''
  # === VSP_RUN_STATUS_MAP_CI_DIR_V2_DEBUG_SAFE ===
  try:
    from pathlib import Path as _Path
    import re as _re
    import datetime as _dt

    def _rid_ts_epoch(_rid: str):
      # RID format: VSP_UIREQ_YYYYmmdd_HHMMSS_xxxxxx
      m = _re.search(r"VSP_UIREQ_(\d{8})_(\d{6})_", _rid or "")
      if not m:
        return None
      s = m.group(1) + m.group(2)  # YYYYmmddHHMMSS
      try:
        dt = _dt.datetime.strptime(s, "%Y%m%d%H%M%S")
        return dt.timestamp()
      except Exception:
        return None

    def _ci_ts_epoch(_name: str):
      # CI dir: VSP_CI_YYYYmmdd_HHMMSS
      m = _re.search(r"VSP_CI_(\d{8})_(\d{6})$", _name or "")
      if not m:
        return None
      s = m.group(1) + m.group(2)
      try:
        dt = _dt.datetime.strptime(s, "%Y%m%d%H%M%S")
        return dt.timestamp()
      except Exception:
        return None

    def _pick_ci_dir_for_target(_target: str, _rid: str):
      t = (_target or "").strip()
      if not t:
        return None
      out_ci = _Path(t) / "out_ci"
      if not out_ci.is_dir():
        return None

      rid_epoch = _rid_ts_epoch(_rid) or None
      cands = []
      for d in out_ci.iterdir():
        if not d.is_dir():
          continue
        if not d.name.startswith("VSP_CI_"):
          continue
        ep = _ci_ts_epoch(d.name)
        # fallback to mtime if cannot parse
        try:
          mtime = d.stat().st_mtime
        except Exception:
          mtime = None
        cands.append((ep, mtime, str(d)))

      if not cands:
        return None

      # prefer timestamp >= rid_ts - 120s and close to rid_ts
      if rid_epoch is not None:
        win = []
        for ep, mt, path in cands:
          if ep is None:
            continue
          if ep >= (rid_epoch - 120) and ep <= (rid_epoch + 6*3600):
            win.append((abs(ep - rid_epoch), ep, mt, path))
        if win:
          win.sort(key=lambda x: (x[0], -(x[1] or 0), -(x[2] or 0)))
          return win[0][3]

      # else pick newest by (parsed_ts, mtime)
      cands.sort(key=lambda x: ((x[0] or 0), (x[1] or 0)))
      return cands[-1][2]

    # main
    if isinstance(st, dict):
      _need = (st.get("ci_run_dir") in ("", None)) or (st.get("runner_log") in ("", None))
      _tgt = st.get("target") or st.get("target_path") or ""
      if _need and _tgt:
        _picked = _pick_ci_dir_for_target(_tgt, req_id)
        if _picked:
          _rl = str(_Path(_picked) / "runner.log")
          if not _Path(_rl).is_file():
            _rl = str(_Path(_picked) / "runner.log")  # keep canonical anyway
          st["ci_run_dir"] = _picked
          st["runner_log"] = _rl if _Path(_rl).exists() else _rl
          st["ci_root_from_pid"] = _tgt
          print(f"[VSP_RUN_STATUS_MAP_CI_DIR_V2_DEBUG_SAFE] req_id={req_id} picked_ci={_picked} runner_log={st.get('runner_log')}")

          # persist back to UIREQ_DIR state file if helper exists
          try:
            # use existing helper if present
            sp = None
            try:
              sp = _state_path_uireq_v1(req_id)  # type: ignore
            except Exception:
              sp = None
            if sp is None:
              # fallback: use _VSP_UIREQ_DIR if available
              try:
                sp = _VSP_UIREQ_DIR / f"{req_id}.json"  # type: ignore
              except Exception:
                sp = None
            if sp is not None:
              _Path(str(sp)).write_text(__import__("json").dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
          except Exception as _pe:
            print(f"[VSP_RUN_STATUS_MAP_CI_DIR_V2_DEBUG_SAFE] persist_err={_pe}")
        else:
          print(f"[VSP_RUN_STATUS_MAP_CI_DIR_V2_DEBUG_SAFE] req_id={req_id} no_ci_dir_found target={_tgt}")
  except Exception as _e:
    try:
      print(f"[VSP_RUN_STATUS_MAP_CI_DIR_V2_DEBUG_SAFE] fatal_err={_e}")
    except Exception:
      pass
  # === END VSP_RUN_STATUS_MAP_CI_DIR_V2_DEBUG_SAFE ===

'''

txt2 = txt[:insert_pos] + block + txt[insert_pos:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
