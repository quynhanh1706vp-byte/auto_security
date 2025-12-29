#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
JS="static/js/vsp_dashboard_cio_kpi_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_DEFAULT="${RID_DEFAULT:-VSP_CI_20251219_092640}"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p963f_${TS}"
mkdir -p "$OUT"
log(){ echo "$*" | tee -a "$OUT/run.log"; }

need(){ command -v "$1" >/dev/null 2>&1 || { log "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need head; need sed; need grep; need awk; need curl

log "== [0] restore vsp_demo_app.py from last known-good (p963b backup) =="
BK="$(ls -1t out_ci/p963b_*/vsp_demo_app.py.bak_* 2>/dev/null | head -n1 || true)"
[ -n "$BK" ] || { log "[FAIL] no p963b backup found under out_ci/p963b_*"; exit 2; }
cp -f "$APP" "$OUT/$(basename "$APP").before_${TS}"
cp -f "$BK" "$APP"
log "[OK] restored from: $BK"

log "== [1] add KPI best-source endpoint: /api/vsp/kpi_counts_v2 =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# ensure Path/json imports exist
if "from pathlib import Path" not in s:
    if s.startswith("#!"):
        lines=s.splitlines(True)
        lines.insert(1, "from pathlib import Path\n")
        s="".join(lines)
    else:
        s="from pathlib import Path\n"+s
if "import json" not in s:
    s="import json\n"+s

marker="### VSP_P963F_KPI_COUNTS_V2 ###"
if marker in s:
    print("[OK] v2 already present")
    p.write_text(s, encoding="utf-8")
    raise SystemExit(0)

code = r'''
''' + marker + r'''
@app.get("/api/vsp/kpi_counts_v2")
def api_vsp_kpi_counts_v2():
    # Pick best source across roots by max findings/items count (non-empty wins)
    rid = (request.args.get("rid") or "").strip()
    if not rid:
        return jsonify({"ok":False,"err":"missing rid","rid":"","counts":{}}), 400

    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]
    cand_rel = [
        "reports/findings_unified_commercial.json",
        "findings_unified_commercial.json",
        "reports/findings_unified.json",
        "findings_unified.json",
    ]

    best_fp = None
    best_items = []
    best_root = None

    for root in roots:
        d = Path(root) / rid
        if not d.is_dir():
            continue
        for rel in cand_rel:
            fp = d / rel
            try:
                if (not fp.is_file()) or fp.stat().st_size < 10:
                    continue
                obj = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
                items = []
                if isinstance(obj, dict):
                    if isinstance(obj.get("findings"), list):
                        items = obj["findings"]
                    elif isinstance(obj.get("items"), list):
                        items = obj["items"]
                elif isinstance(obj, list):
                    items = obj
                if len(items) > len(best_items):
                    best_items = items
                    best_fp = str(fp)
                    best_root = root
                if len(items) > 0:
                    break
            except Exception:
                continue

    if best_fp is None:
        return jsonify({"ok":False,"err":"rid not found on disk","rid":rid,"roots":roots,"counts":{}}), 404

    # counts by severity fields
    out = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}
    def sev(it):
        if not isinstance(it, dict): return ""
        for k in ("severity_norm","sev_norm","severity","sev","level","priority"):
            v = it.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip().upper()
        return ""
    for it in best_items:
        s = sev(it)
        if s in out:
            out[s] += 1

    # degraded (optional)
    run_dir = Path(best_root) / rid
    degraded = None
    fp = run_dir / "degraded_tools.json"
    if fp.is_file():
        try:
            degraded = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            degraded = None

    return jsonify({
        "ok": True,
        "rid": rid,
        "source": best_fp,
        "n": len(best_items),
        "counts": out,
        "degraded": degraded,
    }), 200
'''

# Insert before __main__ if exists, else append
m = re.search(r"\nif\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
if m:
    s = s[:m.start()] + "\n" + code + "\n" + s[m.start():]
else:
    s = s.rstrip() + "\n\n" + code + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] inserted kpi_counts_v2")
PY

log "== [2] wire KPI JS to call kpi_counts_v2 (instead of v1) =="
# safe global replace
sed -i 's|/api/vsp/kpi_counts_v1|/api/vsp/kpi_counts_v2|g' "$JS" || true

log "== [3] py_compile must PASS =="
python3 -m py_compile "$APP"
log "[OK] py_compile PASS"

log "== [4] restart+wait =="
sudo -v || true
sudo systemctl restart "$SVC" || true

ok=0
for i in $(seq 1 45); do
  if ss -lntp 2>/dev/null | grep -q ':8910'; then
    code="$(curl -sS --noproxy '*' -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 3 "$BASE/api/vsp/healthz" || true)"
    log "try#$i LISTEN=1 healthz=$code"
    if [ "$code" = "200" ]; then ok=1; break; fi
  else
    log "try#$i LISTEN=0"
  fi
  sleep 1
done
[ "$ok" = "1" ] || { log "[FAIL] UI not ready"; sudo systemctl status "$SVC" --no-pager -l || true; exit 3; }

log "== [5] test KPI v2 =="
rid="$RID_DEFAULT"
curl -fsS "$BASE/api/vsp/kpi_counts_v2?rid=$rid" | head -c 800 | tee -a "$OUT/kpi_v2.txt"
echo | tee -a "$OUT/kpi_v2.txt"
log "[PASS] done => $OUT"
