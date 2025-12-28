#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node; need curl
command -v systemctl >/dev/null 2>&1 || true

TABS5="static/js/vsp_bundle_tabs5_v1.js"
AUTORID="static/js/vsp_tabs4_autorid_v1.js"
PRETTY3="static/js/vsp_dashboard_charts_pretty_v3.js"
PRETTY4="static/js/vsp_dashboard_charts_pretty_v4.js"
LIVE="static/js/vsp_dashboard_live_v2.V1_baseline.js"

echo "== [0] backups =="
for f in "$TABS5" "$AUTORID" "$PRETTY3" "$PRETTY4" "$LIVE"; do
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_p3k12_${TS}"
    echo "[BACKUP] ${f}.bak_p3k12_${TS}"
  fi
done

"$PY" - <<'PY'
from pathlib import Path
import re

def bump_timeouts(s: str, new_ms: int = 12000) -> str:
    # setTimeout(...abort..., 2000) => 12000 (only when abort() appears)
    def bump_abort(m):
        ms = int(m.group(2))
        return m.group(1) + (str(new_ms) if ms <= 2500 else str(ms)) + m.group(3)

    s = re.sub(
        r'(\bsetTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
        bump_abort, s, flags=re.I
    )

    # timeout/timeoutMs/timeout_ms: 2000 => 12000
    s = re.sub(
        r'((?:timeoutMs|timeout_ms|timeout)\s*[:=]\s*)(\d{1,4})',
        lambda m: m.group(1) + (str(new_ms) if int(m.group(2)) <= 2500 else m.group(2)),
        s, flags=re.I
    )
    return s

def fail_soft_basic(s: str) -> str:
    # Convert pure-line rejects/throws into safe returns (conservative)
    s = re.sub(r'(?m)^\s*return\s+Promise\.reject\([^)]*\)\s*;\s*$', '  return null;', s)
    s = re.sub(r'(?m)^\s*throw\s+\w+\s*;\s*$', '  return null;', s)
    return s

def wrap_optin_script(path: Path, marker: str, enable_expr_js: str, label: str):
    s0 = path.read_text(encoding="utf-8", errors="replace")
    if marker in s0:
        return False

    s = s0

    # Preserve "use strict"; if it exists very early
    strict = ""
    head = s[:300]
    m = re.search(r'^\s*(["\'])use strict\1;\s*', head)
    if m:
        strict = m.group(0)
        s = strict + s[m.end():]

    # Build wrapper: strict stays at file start; original runs only if enabled
    prefix = (
        f"/* {marker} */\n"
        "(function(){\n"
        "  try{\n"
        "    var qp = new URLSearchParams(location.search||\"\");\n"
        f"    window.__VSP_OPTIN_{label}__ = ({enable_expr_js});\n"
        "  }catch(e){ window.__VSP_OPTIN_" + label + "__ = false; }\n"
        "})();\n"
        "if (typeof window !== 'undefined' && window.__VSP_OPTIN_" + label + "__) {\n"
    )
    suffix = "\n}\n"

    out = (strict + prefix + s + suffix)
    path.write_text(out, encoding="utf-8")
    return True

changed = 0

# Patch tabs5
p = Path("static/js/vsp_bundle_tabs5_v1.js")
if p.exists():
    s0 = p.read_text(encoding="utf-8", errors="replace")
    s = s0
    if "VSP_P3K12_TABS5_TIMEOUTS_FAILSOFT_V1" not in s:
        s = "// VSP_P3K12_TABS5_TIMEOUTS_FAILSOFT_V1\n" + s
    s = bump_timeouts(s, 12000)
    s = fail_soft_basic(s)
    s = s.replace("[P2Badges] rid_latest fetch fail timeout", "[P2Badges] rid_latest slow (non-fatal)")
    if s != s0:
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", p)
        changed += 1

# Patch autorid
p = Path("static/js/vsp_tabs4_autorid_v1.js")
if p.exists():
    s0 = p.read_text(encoding="utf-8", errors="replace")
    s = s0
    if "VSP_P3K12_AUTORID_TIMEOUTS_FAILSOFT_V1" not in s:
        s = "// VSP_P3K12_AUTORID_TIMEOUTS_FAILSOFT_V1\n" + s
    s = bump_timeouts(s, 12000)
    s = fail_soft_basic(s)
    if s != s0:
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", p)
        changed += 1

# Opt-in charts_pretty (disable by default, enable via ?charts_pretty=1 or ?pretty=1 or ?charts=1)
for fname, lab in [("static/js/vsp_dashboard_charts_pretty_v3.js","PRETTY"),
                   ("static/js/vsp_dashboard_charts_pretty_v4.js","PRETTY")]:
    p = Path(fname)
    if p.exists():
        ok = wrap_optin_script(
            p,
            "VSP_P3K12_OPTIN_CHARTS_PRETTY_V1",
            "qp.get('charts_pretty')==='1' || qp.get('pretty')==='1' || qp.get('charts')==='1'",
            lab
        )
        if ok:
            print("[OK] wrapped opt-in", p)
            changed += 1

# Opt-in live dashboard (disable by default, enable via ?live=1)
p = Path("static/js/vsp_dashboard_live_v2.V1_baseline.js")
if p.exists():
    ok = wrap_optin_script(
        p,
        "VSP_P3K12_OPTIN_LIVE_V1",
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

echo "== [3] smoke backend fast =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get(\"rid\",\"\"))')"
echo "RID=$RID"
curl -fsS -w "\nHTTP=%{http_code} time=%{time_total}\n" -o /dev/null "$BASE/api/vsp/dashboard_v3_latest?rid=$RID"
curl -fsS -w "\nHTTP=%{http_code} time=%{time_total}\n" -o /dev/null "$BASE/api/vsp/top_findings_v3c?limit=50&rid=$RID"

echo "[DONE] p3k12_commercial_dashboard_safe_mode_v1"
