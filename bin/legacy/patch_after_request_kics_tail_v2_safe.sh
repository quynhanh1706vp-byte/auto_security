#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_afterreq_kics_tail_v2_${TS}"
echo "[BACKUP] $F.bak_afterreq_kics_tail_v2_${TS}"

echo "== [1] ensure vsp_demo_app.py compilable (auto-restore if needed) =="
if python3 -m py_compile "$F" >/dev/null 2>&1; then
  echo "[OK] current file compiles"
else
  echo "[WARN] current file does NOT compile. searching backups..."
  CANDS="$(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true)"
  [ -n "$CANDS" ] || { echo "[ERR] no backups found: vsp_demo_app.py.bak_*"; exit 2; }

  OK_BAK=""
  for B in $CANDS; do
    cp -f "$B" "$F"
    if python3 -m py_compile "$F" >/dev/null 2>&1; then
      OK_BAK="$B"
      break
    fi
  done

  [ -n "$OK_BAK" ] || { echo "[ERR] no compilable backup found"; exit 3; }
  echo "[OK] restored $F <= $OK_BAK"
fi

echo "== [2] patch AFTER_REQUEST KICS tail (V2_SAFE) after app=Flask(...) statement =="
python3 - <<'PY'
import re, json
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_AFTER_REQUEST_KICS_TAIL_V2_SAFE ==="
if TAG in t:
    print("[OK] already patched V2_SAFE")
    raise SystemExit(0)

# remove older/broken attempts (best-effort)
t = re.sub(r"\n?\s*# === VSP_AFTER_REQUEST_KICS_TAIL_V1 ===[\s\S]*?# === END VSP_AFTER_REQUEST_KICS_TAIL_V1 ===\s*\n?", "\n", t, flags=re.S)
t = re.sub(r"\n?\s*# === VSP_AFTER_REQUEST_KICS_TAIL_V2_SAFE ===[\s\S]*?# === END VSP_AFTER_REQUEST_KICS_TAIL_V2_SAFE ===\s*\n?", "\n", t, flags=re.S)

lines = t.splitlines(True)

# find 'app = Flask('
app_i = None
app_ind = ""
for i, s in enumerate(lines):
    m = re.match(r"^([ \t]*)app\s*=\s*Flask\s*\(", s)
    if m:
        app_i = i
        app_ind = m.group(1)
        break

def find_stmt_end(start_i: int):
    # scan for matching ')' balance from start_i
    balance = 0
    started = False
    in_str = None  # "'", '"', "'''", '"""'
    esc = False
    for j in range(start_i, len(lines)):
        s = lines[j]
        k = 0
        while k < len(s):
            ch = s[k]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                else:
                    if in_str in ("'''",'"""'):
                        if s.startswith(in_str, k):
                            in_str = None
                            k += len(in_str or "") - 1
                    else:
                        if ch == in_str:
                            in_str = None
                k += 1
                continue

            # not in string
            if s.startswith("'''", k):
                in_str = "'''"
                k += 3
                continue
            if s.startswith('"""', k):
                in_str = '"""'
                k += 3
                continue
            if ch == "'":
                in_str = "'"
                k += 1
                continue
            if ch == '"':
                in_str = '"'
                k += 1
                continue

            if ch == "(":
                balance += 1
                started = True
            elif ch == ")":
                if balance > 0:
                    balance -= 1
            k += 1

        if started and balance == 0:
            return j
    return None

insert_at = None
if app_i is not None:
    end_i = find_stmt_end(app_i)
    if end_i is not None:
        insert_at = end_i + 1

# fallback: insert before first @app.route if cannot detect end of statement
if insert_at is None:
    for i, s in enumerate(lines):
        if re.match(r"^\s*@app\.", s):
            insert_at = i
            break

if insert_at is None:
    insert_at = len(lines)

block = f"""{app_ind}{TAG}
{app_ind}def _vsp__kics_tail_from_ci(ci_run_dir: str, max_bytes: int = 65536) -> str:
{app_ind}    try:
{app_ind}        import os
{app_ind}        from pathlib import Path
{app_ind}        NL = chr(10)
{app_ind}        klog = os.path.join(ci_run_dir, "kics", "kics.log")
{app_ind}        if not os.path.exists(klog):
{app_ind}            return ""
{app_ind}        rawb = Path(klog).read_bytes()
{app_ind}        if len(rawb) > max_bytes:
{app_ind}            rawb = rawb[-max_bytes:]
{app_ind}        raw = rawb.decode("utf-8", errors="ignore").replace(chr(13), NL)
{app_ind}        # keep last non-empty lines (avoid spinner noise)
{app_ind}        lines2 = [x for x in raw.splitlines() if x.strip()]
{app_ind}        tail = NL.join(lines2[-60:])
{app_ind}        # pick latest HB/rc marker
{app_ind}        hb = ""
{app_ind}        for ln in reversed(lines2):
{app_ind}            if ("[KICS_V" in ln and "][HB]" in ln) or ("[KICS_V" in ln and "rc=" in ln) or ("[DEGRADED]" in ln):
{app_ind}                hb = ln.strip()
{app_ind}                break
{app_ind}        if hb and hb not in tail:
{app_ind}            tail = hb + NL + tail
{app_ind}        return tail[-4096:]
{app_ind}    except Exception:
{app_ind}        return ""

{app_ind}def _vsp__load_ci_dir_from_state(req_id: str) -> str:
{app_ind}    try:
{app_ind}        import json
{app_ind}        from pathlib import Path
{app_ind}        base = Path(__file__).resolve().parent
{app_ind}        cands = [
{app_ind}            base / "out_ci" / "uireq_v1" / (req_id + ".json"),
{app_ind}            base / "ui" / "out_ci" / "uireq_v1" / (req_id + ".json"),
{app_ind}            base / "out_ci" / "ui_req_state" / (req_id + ".json"),
{app_ind}            base / "ui" / "out_ci" / "ui_req_state" / (req_id + ".json"),
{app_ind}        ]
{app_ind}        for fp in cands:
{app_ind}            if fp.exists():
{app_ind}                txt = fp.read_text(encoding="utf-8", errors="ignore") or ""
{app_ind}                j = json.loads(txt) if txt.strip() else {{}}
{app_ind}                ci = str(j.get("ci_run_dir") or "")
{app_ind}                if ci:
{app_ind}                    return ci
{app_ind}        return ""
{app_ind}    except Exception:
{app_ind}        return ""

{app_ind}def _vsp__after_request_kics_tail(resp):
{app_ind}    try:
{app_ind}        import json
{app_ind}        from flask import request
{app_ind}        if not request.path.startswith("/api/vsp/run_status_v1/"):
{app_ind}            return resp
{app_ind}        # only patch JSON responses
{app_ind}        if (getattr(resp, "mimetype", "") or "") != "application/json":
{app_ind}            return resp
{app_ind}        rid = request.path.rsplit("/", 1)[-1]
{app_ind}        data = resp.get_data(as_text=True) or ""
{app_ind}        obj = json.loads(data) if data.strip() else {{}}
{app_ind}        stage = str(obj.get("stage_name") or "").lower()
{app_ind}        ci = str(obj.get("ci_run_dir") or "")
{app_ind}        if not ci:
{app_ind}            ci = _vsp__load_ci_dir_from_state(rid)
{app_ind}        if ci and ("kics" in stage):
{app_ind}            kt = _vsp__kics_tail_from_ci(ci)
{app_ind}            if kt:
{app_ind}                obj["kics_tail"] = kt
{app_ind}                resp.set_data(json.dumps(obj, ensure_ascii=False))
{app_ind}                resp.headers["Content-Length"] = str(len(resp.get_data()))
{app_ind}        return resp
{app_ind}    except Exception:
{app_ind}        return resp

{app_ind}try:
{app_ind}    app.after_request(_vsp__after_request_kics_tail)
{app_ind}except Exception:
{app_ind}    pass
{app_ind}# === END VSP_AFTER_REQUEST_KICS_TAIL_V2_SAFE ===
"""

lines.insert(insert_at, block if block.endswith("\n") else (block + "\n"))
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] inserted V2_SAFE at line ~{insert_at+1}")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"

echo "== [3] restart 8910 =="
pkill -f "vsp_demo_app.py" >/dev/null 2>&1 || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz || true
echo
echo "[OK] done"
