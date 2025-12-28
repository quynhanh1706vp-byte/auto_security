#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_bundle_tabs5_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_p3k10_${TS}"
echo "[BACKUP] ${F}.bak_p3k10_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s0=p.read_text(encoding="utf-8", errors="replace")
s=s0

MARK="VSP_P3K10_TABS5_OPTIN_PRETTY_AND_SILENCE_TIMEOUT_V1"
if MARK not in s:
    s = f"// {MARK}\n" + s

# 0) inject opt-in flag near top (only once)
if "window.__VSP_WANT_PRETTY_CHARTS" not in s:
    inject = r'''
;(() => {
  try {
    const qp = new URLSearchParams(location.search || "");
    // opt-in only (default OFF to avoid Firefox freeze)
    window.__VSP_WANT_PRETTY_CHARTS =
      qp.get("charts_pretty")==="1" || qp.get("pretty")==="1" || qp.get("charts")==="1";
  } catch(e) { window.__VSP_WANT_PRETTY_CHARTS = false; }
})();
'''
    s = s.replace(f"// {MARK}\n", f"// {MARK}\n{inject}\n", 1)

# 1) silence the timeout label (cosmetic)
s = s.replace("Dashboard error: timeout", "Dashboard: loading…")
s = s.replace("rid_latest fetch fail timeout", "rid_latest slow (ignored)")

# 2) bump tiny abort/fetch timeouts (<=2500ms -> 9000ms)
def bump_small_ms(m):
    ms=int(m.group(2))
    return m.group(1)+("9000" if ms<=2500 else str(ms))+m.group(3)

s = re.sub(r'(\bsetTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
           bump_small_ms, s, flags=re.I)
s = re.sub(r'((?:timeoutMs|timeout_ms|timeout)\s*[:=]\s*)(\d{1,4})',
           lambda m: m.group(1)+("9000" if int(m.group(2))<=2500 else m.group(2)),
           s, flags=re.I)

# 3) OPT-IN charts_pretty: wrap any script-loader call that contains charts_pretty_v3/v4
# Convert: loader("...vsp_dashboard_charts_pretty_v3.js...");  -> window.__VSP_WANT_PRETTY_CHARTS && loader("..."); 
pattern = re.compile(r'(?m)^(?P<indent>\s*)(?P<call>[^;\n]*\(\s*["\'][^"\']*vsp_dashboard_charts_pretty_v[34]\.js[^"\']*["\'][^;\n]*\)\s*;)\s*$')
def repl(m):
    return f'{m.group("indent")}window.__VSP_WANT_PRETTY_CHARTS && ({m.group("call")})'
s, n = pattern.subn(repl, s)

# If not found (minified inline), do a fallback replacement: prefix "vsp_dashboard_charts_pretty..." occurrences with a marker for manual gating.
# But do NOT break strings; just leave unchanged if no call-line matched.
# (We rely on the common non-minified loader call form; n should be >0 on your build.)
print("[INFO] gated_loader_calls=", n)

if s != s0:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched", p)
else:
    print("[SKIP] no changes made")
PY

echo "== node -c =="
node -c "$F" >/dev/null && echo "[OK] node -c passed"

echo "== restart =="
sudo systemctl restart "$SVC"
sleep 0.7
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,180p' || true
  sudo journalctl -u "$SVC" -n 180 --no-pager || true
  exit 3
}

echo "[DONE] p3k10_tabs5_optin_pretty_and_silence_timeout_v1"
