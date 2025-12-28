#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node; need curl; need "$PY"
command -v systemctl >/dev/null 2>&1 || true

TABS5="static/js/vsp_bundle_tabs5_v1.js"
AUTORID="static/js/vsp_tabs4_autorid_v1.js"
PRETTY3="static/js/vsp_dashboard_charts_pretty_v3.js"
PRETTY4="static/js/vsp_dashboard_charts_pretty_v4.js"
LIVE="static/js/vsp_dashboard_live_v2.V1_baseline.js"

echo "== [0] backups =="
for f in "$TABS5" "$AUTORID" "$PRETTY3" "$PRETTY4" "$LIVE"; do
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_p3k12v2_${TS}"
    echo "[BACKUP] ${f}.bak_p3k12v2_${TS}"
  fi
done

"$PY" - <<'PY'
from pathlib import Path
import re

def bump_timeouts(s: str, new_ms: int = 12000) -> str:
    def bump_abort(m):
        ms = int(m.group(2))
        return m.group(1) + (str(new_ms) if ms <= 2500 else str(ms)) + m.group(3)

    s = re.sub(
        r'(\bsetTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
        bump_abort, s, flags=re.I
    )
    s = re.sub(
        r'((?:timeoutMs|timeout_ms|timeout)\s*[:=]\s*)(\d{1,4})',
        lambda m: m.group(1) + (str(new_ms) if int(m.group(2)) <= 2500 else m.group(2)),
        s, flags=re.I
    )
    return s

def fail_soft_basic(s: str) -> str:
    s = re.sub(r'(?m)^\s*return\s+Promise\.reject\([^)]*\)\s*;\s*$', '  return null;', s)
    s = re.sub(r'(?m)^\s*throw\s+\w+\s*;\s*$', '  return null;', s)
    return s

def wrap_optin_script(path: Path, marker: str, enable_expr_js: str, label: str) -> bool:
    s0 = path.read_text(encoding="utf-8", errors="replace")
    if marker in s0:
        return False

    s = s0
    strict = ""
    head = s[:400]
    m = re.search(r'^\s*(["\'])use strict\1;\s*', head)
    if m:
        strict = m.group(0)
        s = strict + s[m.end():]

    prefix = (
        f"/* {marker} */\n"
        "(function(){\n"
        "  try{\n"
        "    var qp = new URLSearchParams(location.search||\"\");\n"
        f"    window.__VSP_OPTIN_{label}__ = ({enable_expr_js});\n"
        f"  }}catch(e){{ window.__VSP_OPTIN_{label}__ = false; }}\n"
        "})();\n"
        f"if (typeof window !== 'undefined' && window.__VSP_OPTIN_{label}__) {{\n"
    )
    suffix = "\n}\n"

    path.write_text(strict + prefix + s[len(strict):] + suffix, encoding="utf-8")
    return True

changed = 0

# tabs5
p = Path("static/js/vsp_bundle_tabs5_v1.js")
if p.exists():
    s0 = p.read_text(encoding="utf-8", errors="replace")
    s = s0
    if "VSP_P3K12_V2_TABS5" not in s:
        s = "// VSP_P3K12_V2_TABS5\n" + s
    s = bump_timeouts(s, 12000)
    s = fail_soft_basic(s)
    s = s.replace("[P2Badges] rid_latest fetch fail timeout", "[P2Badges] rid_latest slow (non-fatal)")
    if s != s0:
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", p)
        changed += 1

# autorid
p = Path("static/js/vsp_tabs4_autorid_v1.js")
if p.exists():
    s0 = p.read_text(encoding="utf-8", errors="replace")
    s = s0
    if "VSP_P3K12_V2_AUTORID" not in s:
        s = "// VSP_P3K12_V2_AUTORID\n" + s
    s = bump_timeouts(s, 12000)
    s = fail_soft_basic(s)
    if s != s0:
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", p)
        changed += 1

# opt-in pretty
for fname in ("static/js/vsp_dashboard_charts_pretty_v3.js", "static/js/vsp_dashboard_charts_pretty_v4.js"):
    p = Path(fname)
    if p.exists():
        ok = wrap_optin_script(
            p,
            "VSP_P3K12_V2_OPTIN_CHARTS_PRETTY",
            "qp.get('charts_pretty')==='1' || qp.get('pretty')==='1' || qp.get('charts')==='1'",
            "PRETTY"
        )
        if ok:
            print("[OK] wrapped opt-in", p)
            changed += 1

# opt-in live
p = Path("static/js/vsp_dashboard_live_v2.V1_baseline.js")
if p.exists():
    ok = wrap_optin_script(
        p,
        "VSP_P3K12_V2_OPTIN_LIVE",
        "qp.get('live')==='1'",
        "LIVE"
    )
    if ok:
        print("[OK] wrapped opt-in", p)
        changed += 1

print("[DONE] changed_files=", changed)
PY

echo "== [1] node -c sanity =="
for f in "$TABS5" "$AUTORID" "$PRETTY3" "$PRETTY4" "$LIVE"; do
  [ -f "$f" ] || continue
  node -c "$f" >/dev/null
  echo "[OK] node -c: $f"
done

echo "== [2] restart =="
sudo systemctl restart "$SVC"
sleep 0.8
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,180p' || true
  sudo journalctl -u "$SVC" -n 180 --no-pager || true
  exit 3
}

echo "== [3] smoke backend fast (retry-safe) =="
RID=""
for i in 1 2 3 4 5; do
  body="$(curl -fsS --connect-timeout 1 --max-time 4 "$BASE/api/vsp/rid_latest" 2>/dev/null || true)"
  if echo "$body" | grep -q '^{'; then
    RID="$(echo "$body" | "$PY" -c 'import sys,json; print((json.load(sys.stdin) or {}).get("rid",""))')"
    break
  fi
  echo "[WARN] rid_latest empty/invalid (try $i/5)"
  sleep 0.4
done
echo "RID=$RID"
[ -n "$RID" ] || { echo "[FAIL] cannot read RID"; exit 2; }

curl -fsS -w "\nHTTP=%{http_code} time=%{time_total}\n" -o /dev/null "$BASE/api/vsp/dashboard_v3_latest?rid=$RID"
curl -fsS -w "\nHTTP=%{http_code} time=%{time_total}\n" -o /dev/null "$BASE/api/vsp/top_findings_v3c?limit=50&rid=$RID"

echo "[DONE] p3k12_commercial_dashboard_safe_mode_v2"
