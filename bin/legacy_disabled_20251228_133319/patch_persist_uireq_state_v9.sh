#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # .../SECURITY_BUNDLE/ui
CANDIDATES=(
  "$ROOT/vsp_demo_app.py"
  "$ROOT/my_flask_app/app.py"
)

pick=""
for f in "${CANDIDATES[@]}"; do
  if [ -f "$f" ] && grep -qE "/api/vsp/run_v1|run_v1" "$f"; then
    pick="$f"
    break
  fi
done

[ -n "$pick" ] || { echo "[ERR] cannot locate UI app file containing run_v1 handler"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$pick" "$pick.bak_persist_uireq_v9_${TS}"
echo "[BACKUP] $pick.bak_persist_uireq_v9_${TS}"

python3 - "$pick" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_UIREQ_PERSIST_V9" in txt:
    print("[OK] already patched (V9).")
    raise SystemExit(0)

helper = r'''
# === VSP_UIREQ_PERSIST_V9 ===
from pathlib import Path as _Path
import json as _json
import time as _time
import os as _os

def _uireq_state_dir_v9():
    base = _Path(__file__).resolve().parent
    d = base / "out_ci" / "uireq_v1"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _uireq_state_path_v9(req_id: str):
    return _uireq_state_dir_v9() / f"{req_id}.json"

def _uireq_state_update_v9(req_id: str, patch: dict):
    try:
        fp = _uireq_state_path_v9(req_id)
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
            app.logger.exception("[UIREQ][V9] persist update failed")
        except Exception:
            pass
        return False
# === END VSP_UIREQ_PERSIST_V9 ===
'''.lstrip("\n")

# insert helper after imports (best-effort)
m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', txt, flags=re.M)
if m:
    ins = m.end()
    txt = txt[:ins] + "\n" + helper + "\n" + txt[ins:]
else:
    lines = txt.splitlines(True)
    txt = "".join(lines[:1]) + "\n" + helper + "\n" + "".join(lines[1:])

# hook before return jsonify(...) that includes status_url
pos = txt.find('"status_url"')
if pos == -1:
    pos = txt.find("'status_url'")
if pos == -1:
    print("[ERR] cannot find status_url key in file; cannot hook safely.")
    raise SystemExit(3)

before = txt[:pos]
rets = list(re.finditer(r'^\s*return\s+jsonify\s*\(', before, flags=re.M))
if not rets:
    rets = list(re.finditer(r'^\s*return\s+.*jsonify\s*\(', before, flags=re.M))
if not rets:
    print("[ERR] cannot find return jsonify(...) before status_url.")
    raise SystemExit(4)

ret = rets[-1]

hook = r'''
    # === VSP_UIREQ_PERSIST_V9 hook (run_v1) ===
    try:
        _uireq_state_update_v9(
            locals().get("req_id") or locals().get("request_id"),
            {
              "ci_run_dir": locals().get("ci_run_dir"),
              "runner_log": locals().get("runner_log"),
              "status_url": locals().get("status_url"),
              "status": locals().get("status"),
              "final": locals().get("final"),
              "error": locals().get("error"),
            },
        )
    except Exception:
        pass
    # === END VSP_UIREQ_PERSIST_V9 hook (run_v1) ===
'''.lstrip("\n")

txt = txt[:ret.start()] + hook + "\n" + txt[ret.start():]
p.write_text(txt, encoding="utf-8")
print(f"[OK] patched persist hook into {p.name} (V9).")
PY

echo "== PY COMPILE CHECK =="
python3 -m py_compile "$pick" && echo "[OK] py_compile passed"

echo "== QUICK GREP (UIREQ V9) =="
grep -n "VSP_UIREQ_PERSIST_V9" "$pick" | head -n 60 || true

echo "[DONE] Restart 8910 then run /api/vsp/run_v1 and verify JSON state file."
