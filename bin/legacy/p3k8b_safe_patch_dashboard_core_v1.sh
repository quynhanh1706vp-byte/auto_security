#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node
command -v systemctl >/dev/null 2>&1 || true

# Patch only core files (avoid "scan all JS" that may blow up)
candidates=(
  static/js/vsp_bundle_tabs5_v1.js
  static/js/vsp_dashboard_comm_enhance_v1.js
  static/js/vsp_dashboard_luxe_v1.js
  static/js/vsp_dashboard_live_v2.V1_baseline.js
  static/js/vsp_dashboard_charts_pretty_v3.js
  static/js/vsp_dashboard_charts_pretty_v4.js
)

files=()
for f in "${candidates[@]}"; do
  [ -f "$f" ] && files+=("$f")
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "[ERR] no candidate JS found under static/js/"
  exit 2
fi

echo "== [0] backup =="
for f in "${files[@]}"; do
  cp -f "$f" "${f}.bak_p3k8b_${TS}"
  echo "[BACKUP] ${f}.bak_p3k8b_${TS}"
done

NEW_MS=8000 "$PY" - <<'PY'
from pathlib import Path
import os, re

NEW_MS = int(os.environ.get("NEW_MS","8000"))
MARK = "VSP_P3K8B_SAFE_CORE_V1"

def bump_timeouts(s: str) -> str:
    # setTimeout(() => ctrl.abort(), 800)
    s = re.sub(
        r'(setTimeout\s*\(\s*[^)]*?\babort\s*\(\s*\)\s*[^)]*?,\s*)(\d{1,4})(\s*\))',
        lambda m: m.group(1) + (str(NEW_MS) if int(m.group(2)) <= 2500 else m.group(2)) + m.group(3),
        s,
        flags=re.I
    )
    # timeoutMs: 800 / timeout: 800 / timeoutMs=800 / timeout=800
    s = re.sub(
        r'((?:timeoutMs|timeout_ms|timeout)\s*[:=]\s*)(\d{1,4})',
        lambda m: m.group(1) + (str(NEW_MS) if int(m.group(2)) <= 2500 else m.group(2)),
        s,
        flags=re.I
    )
    return s

def inject_p2badges_disable(s: str) -> str:
    # Ensure P2Badges doesn't run unless ?badges=1
    if "P2Badges" not in s:
        return s
    if "VSP_P3K7" in s or "VSP_P3K8B_P2BADGES_GUARD" in s:
        return s
    guard = """// VSP_P3K8B_P2BADGES_GUARD
(function(){
  try {
    const u = new URL(location.href);
    if (u.searchParams.get("badges") === "1") return; // debug
  } catch(e) {}
  window.__VSP_DISABLE_P2BADGES = 1;
})();
"""
    # Add guard at very top, and also patch the specific log string (optional)
    s2 = guard + "\n" + s
    s2 = s2.replace("[P2Badges] rid_latest fetch fail timeout", "[P2Badges] rid_latest fetch fail (ignored)")
    # Add a very cheap “short-circuit” near log usage if present
    s2 = re.sub(
        r'(\[P2Badges\])',
        r'\1',  # no-op, just keep
        s2
    )
    return s2

def silence_timeout_label(s: str) -> str:
    # Remove visible string
    if "Dashboard error: timeout" in s:
        s = s.replace("Dashboard error: timeout", "")
    return s

def patch_file(path: Path):
    s0 = path.read_text(encoding="utf-8", errors="replace")
    s = s0

    if MARK not in s:
        s = f"// {MARK}\n" + s

    s = silence_timeout_label(s)
    s = bump_timeouts(s)

    # Only for tabs bundle file
    if path.name == "vsp_bundle_tabs5_v1.js":
        s = inject_p2badges_disable(s)

    if s != s0:
        path.write_text(s, encoding="utf-8")
        print("[OK] patched", path)
    else:
        print("[SKIP] no change", path)

paths = [
  "static/js/vsp_bundle_tabs5_v1.js",
  "static/js/vsp_dashboard_comm_enhance_v1.js",
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_dashboard_live_v2.V1_baseline.js",
  "static/js/vsp_dashboard_charts_pretty_v3.js",
  "static/js/vsp_dashboard_charts_pretty_v4.js",
]
for p in paths:
    fp = Path(p)
    if fp.exists():
        patch_file(fp)
PY

echo "== [1] node -c sanity =="
for f in "${files[@]}"; do
  node -c "$f" >/dev/null
  echo "[OK] node -c: $f"
done

echo "== [2] restart =="
sudo systemctl restart "$SVC"
sleep 0.7
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 3
}

echo "[DONE] p3k8b_safe_patch_dashboard_core_v1"
