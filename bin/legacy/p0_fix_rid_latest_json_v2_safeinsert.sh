#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_ridlatest_safe_${TS}"
echo "[BACKUP] ${WSGI}.bak_ridlatest_safe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RID_LATEST_JSON_V2_SAFEINSERT"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# find app creation
m = re.search(r'^(?P<indent>\s*)app\s*=\s*Flask\s*\(', s, re.M)
if not m:
    raise SystemExit("[ERR] cannot find `app = Flask(` in wsgi_vsp_ui_gateway.py")

insert_at = m.end()
# insert after the whole line (to line end)
line_end = s.find("\n", m.start())
if line_end == -1:
    line_end = len(s)
insert_at = line_end + 1

block = r'''
# ===================== {MARK} =====================
# Contract: /api/vsp/rid_latest must always return JSON (never HTML/empty)
@app.route("/api/vsp/rid_latest")
def vsp_rid_latest():
    import json, time
    from pathlib import Path
    try:
        base = Path(__file__).resolve().parent
        root = base.parent
        candidates = [
            root/"out", root/"out_ci",
            base/"out", base/"out_ci",
            Path("/home/test/Data/SECURITY_BUNDLE/out"),
            Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        ]
        best = None  # (mtime, rid)
        for d in candidates:
            if not d.exists() or not d.is_dir():
                continue
            for sub in d.iterdir():
                if not sub.is_dir():
                    continue
                rid = sub.name
                if not (rid.startswith("VSP_") or rid.startswith("RUN_") or ("VSP_CI_" in rid)):
                    continue
                ok = False
                for rel in ("run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"):
                    if (sub/rel).exists():
                        ok = True; break
                if not ok and ((sub/"reports").exists() or (sub/"findings_unified.json").exists() or (sub/"reports/findings_unified.json").exists()):
                    ok = True
                if not ok:
                    continue
                mt = sub.stat().st_mtime
                if (best is None) or (mt > best[0]):
                    best = (mt, rid)
        out = {"ok": bool(best), "rid": (best[1] if best else ""), "via":"fs", "ts": int(time.time())}
    except Exception:
        out = {"ok": False, "rid": "", "via":"err", "ts": int(time.time())}

    body = json.dumps(out, ensure_ascii=False)
    return (body, 200, {"Content-Type":"application/json; charset=utf-8", "Cache-Control":"no-store"})
# =================== end {MARK} ===================
'''.strip("\n").replace("{MARK}", MARK) + "\n\n"

s2 = s[:insert_at] + block + s[insert_at:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

systemctl restart "$SVC" || true
sleep 0.6
curl -fsS "$BASE/api/vsp/rid_latest"; echo
