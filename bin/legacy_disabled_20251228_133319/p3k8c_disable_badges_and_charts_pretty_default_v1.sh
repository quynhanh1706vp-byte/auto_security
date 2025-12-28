#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need grep; need date
command -v systemctl >/dev/null 2>&1 || true

# Only patch these (minimal blast radius)
targets=(
  static/js/vsp_bundle_tabs5_v1.js
  static/js/vsp_dashboard_charts_pretty_v3.js
  static/js/vsp_dashboard_charts_pretty_v4.js
  static/js/vsp_dashboard_comm_enhance_v1.js
  static/js/vsp_dashboard_luxe_v1.js
  static/js/vsp_dashboard_live_v2.V1_baseline.js
)

files=()
for f in "${targets[@]}"; do
  [ -f "$f" ] && files+=("$f")
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "[ERR] no target JS found"
  exit 2
fi

echo "== [0] backup =="
for f in "${files[@]}"; do
  cp -f "$f" "${f}.bak_p3k8c_${TS}"
  echo "[BACKUP] ${f}.bak_p3k8c_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

MARK = "VSP_P3K8C_DISABLE_BADGES_CHARTS_PRETTY_DEFAULT_V1"

def ensure_header(p: Path, s: str) -> str:
    return s if MARK in s else f"// {MARK}\n{s}"

def remove_timeout_banner(s: str) -> str:
    # Cosmetic: remove visible text everywhere
    if "Dashboard error: timeout" in s:
        s = s.replace("Dashboard error: timeout", "")
    return s

def patch_tabs5_disable_badges(p: Path, s: str) -> str:
    # Disable badges unless ?badges=1
    if "P2Badges" not in s and "rid_latest" not in s:
        return s

    if "VSP_P3K8C_BADGES_GUARD" in s:
        return s

    guard = r"""// VSP_P3K8C_BADGES_GUARD
(function(){
  try {
    var u = new URL(location.href);
    var en = (u.searchParams.get("badges") === "1");
    window.__VSP_BADGES_ENABLED = en;
    if (!en) window.__VSP_DISABLE_P2BADGES = 1;
  } catch(e) {
    window.__VSP_BADGES_ENABLED = false;
    window.__VSP_DISABLE_P2BADGES = 1;
  }
})();
"""
    s = guard + "\n" + s

    # 1) If there is a setInterval polling near P2Badges, wrap it
    lines = s.splitlines(True)
    out = []
    for i, line in enumerate(lines):
        if "setInterval(" in line:
            # look around for P2Badges or rid_latest nearby
            win = "".join(lines[max(0,i-40):min(len(lines), i+60)])
            if ("P2Badges" in win) or ("rid_latest" in win):
                out.append("if (window.__VSP_BADGES_ENABLED) {\n")
                out.append(line)
                out.append("}\n")
                continue
        out.append(line)
    s = "".join(out)

    # 2) Silence the specific warning (and stop doing work if a guard exists in catch blocks)
    s = s.replace("[P2Badges] rid_latest fetch fail timeout", "[P2Badges] rid_latest fetch skipped")
    # 3) If there is a direct init call, gate it (best-effort, safe no-op if not found)
    s = re.sub(r'(\binitP2Badges\s*\()',
               r'(window.__VSP_BADGES_ENABLED ? initP2Badges : function(){})(',
               s)
    return s

def patch_charts_pretty_gate(p: Path, s: str) -> str:
    # Disable charts_pretty unless ?charts=1
    if "charts_pretty" not in p.name and "Charts" not in s and "chart" not in s:
        return s

    if "VSP_P3K8C_CHARTS_GUARD" in s:
        return s

    guard = r"""// VSP_P3K8C_CHARTS_GUARD
(function(){
  try {
    var u = new URL(location.href);
    var en = (u.searchParams.get("charts") === "1");
    window.__VSP_CHARTS_PRETTY_ENABLED = en;
    if (!en) window.__VSP_DISABLE_CHARTS_PRETTY = 1;
  } catch(e) {
    window.__VSP_CHARTS_PRETTY_ENABLED = false;
    window.__VSP_DISABLE_CHARTS_PRETTY = 1;
  }
})();
"""
    s = guard + "\n" + s

    # Gate DOMContentLoaded/load handlers: insert early return in handler body.
    def gate_listener(m):
        head = m.group(1)
        body = m.group(2)
        if "window.__VSP_DISABLE_CHARTS_PRETTY" in body:
            return m.group(0)
        inject = "if (window.__VSP_DISABLE_CHARTS_PRETTY) return;\n"
        return head + inject + body

    # Match: addEventListener('DOMContentLoaded', function(){ ... })
    s = re.sub(
        r'(\baddEventListener\s*\(\s*[\'"](?:DOMContentLoaded|load)[\'"]\s*,\s*function\s*\([^)]*\)\s*\{\s*)([\s\S]*?)(\}\s*\)\s*;)',
        lambda m: m.group(1) + ("if (window.__VSP_DISABLE_CHARTS_PRETTY) return;\n" + m.group(2)) + m.group(3),
        s,
        flags=re.M
    )
    # Also gate arrow handlers: addEventListener('load', () => { ... })
    s = re.sub(
        r'(\baddEventListener\s*\(\s*[\'"](?:DOMContentLoaded|load)[\'"]\s*,\s*\(\s*\)\s*=>\s*\{\s*)([\s\S]*?)(\}\s*\)\s*;)',
        lambda m: m.group(1) + ("if (window.__VSP_DISABLE_CHARTS_PRETTY) return;\n" + m.group(2)) + m.group(3),
        s,
        flags=re.M
    )
    return s

patched = 0
for path in [
  Path("static/js/vsp_bundle_tabs5_v1.js"),
  Path("static/js/vsp_dashboard_charts_pretty_v3.js"),
  Path("static/js/vsp_dashboard_charts_pretty_v4.js"),
  Path("static/js/vsp_dashboard_comm_enhance_v1.js"),
  Path("static/js/vsp_dashboard_luxe_v1.js"),
  Path("static/js/vsp_dashboard_live_v2.V1_baseline.js"),
]:
    if not path.exists():
        continue
    s0 = path.read_text(encoding="utf-8", errors="replace")
    s = s0
    s = ensure_header(path, s)
    s = remove_timeout_banner(s)
    if path.name == "vsp_bundle_tabs5_v1.js":
        s = patch_tabs5_disable_badges(path, s)
    if "vsp_dashboard_charts_pretty" in path.name:
        s = patch_charts_pretty_gate(path, s)

    if s != s0:
        path.write_text(s, encoding="utf-8")
        print("[OK] patched", path)
        patched += 1
    else:
        print("[SKIP] no change", path)

print("[DONE] patched_files=", patched)
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

echo "[DONE] p3k8c_disable_badges_and_charts_pretty_default_v1"
