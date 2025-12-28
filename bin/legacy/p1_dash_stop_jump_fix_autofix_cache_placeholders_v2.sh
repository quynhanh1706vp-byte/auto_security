#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

TPL="templates/vsp_dashboard_2025.html"
BUNDLE="static/js/vsp_bundle_commercial_v2.js"
RIDFIX="static/js/vsp_rid_autofix_v1.js"
POLISH="static/css/vsp_dashboard_polish_v1.css"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

# 1) Force rid_autofix to true NO-OP (and visible log)
mkdir -p "$(dirname "$RIDFIX")"
if [ -f "$RIDFIX" ]; then
  cp -f "$RIDFIX" "${RIDFIX}.bak_noopforce_${TS}"
  echo "[BACKUP] ${RIDFIX}.bak_noopforce_${TS}"
fi

cat > "$RIDFIX" <<'JS'
/* VSP_NOOP_RID_AUTOFIX_FORCE_V2
 * Commercial Dashboard contract: rid comes ONLY from /api/vsp/rid_latest_gate_root (DashCommercialV1),
 * NEVER from this legacy rid_autofix module.
 */
(()=> {
  if (window.__vsp_noop_rid_autofix_force_v2) return;
  window.__vsp_noop_rid_autofix_force_v2 = true;
  try { console.info("[VSP] rid_autofix DISABLED (noop force v2)"); } catch(e){}
})();
JS

# 2) Patch template safely (no tricky quote-regex): remove rid_autofix line(s),
#    bust cache for bundle/polish, and add hidden placeholder containers to stop STABLE_V1 retry/jump.
cp -f "$TPL" "${TPL}.bak_stopjump_${TS}"
echo "[BACKUP] ${TPL}.bak_stopjump_${TS}"

python3 - <<PY
from pathlib import Path
import re, html

ts = "${TS}"
tpl = Path("${TPL}")
bundle_text = Path("${BUNDLE}").read_text(encoding="utf-8", errors="replace")

s = tpl.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

# remove any script tag line that references rid_autofix (line-based == safest)
lines2 = [ln for ln in lines if "vsp_rid_autofix_v1.js" not in ln]
s2 = "".join(lines2)

# inject boot flags (helps future guards)
bootflag = '<script>window.__VSP_DASH_MODE="commercial";window.__VSP_DISABLE_RID_AUTOFIX=true;</script>'
if "__VSP_DASH_MODE" not in s2:
    s2 = re.sub(r"(</head>)", bootflag + "\\n\\1", s2, flags=re.I)

# ensure polish css exists and bust cache
polish_link = f'<link rel="stylesheet" href="/static/css/vsp_dashboard_polish_v1.css?v={ts}"/>'
if "vsp_dashboard_polish_v1.css" not in s2:
    s2 = re.sub(r"(</head>)", polish_link + "\\n\\1", s2, flags=re.I)
else:
    s2 = re.sub(r"/static/css/vsp_dashboard_polish_v1\\.css(?:\\?v=[^\"']+)?",
                f"/static/css/vsp_dashboard_polish_v1.css?v={ts}", s2)

# bust cache for bundle
if "vsp_bundle_commercial_v2.js" in s2:
    s2 = re.sub(r"/static/js/vsp_bundle_commercial_v2\\.js(?:\\?v=[^\"']+)?",
                f"/static/js/vsp_bundle_commercial_v2.js?v={ts}", s2)

# extract missing container ids from bundle logs: "missing containers: a,b,c"
ids = set()
for m in re.finditer(r"missing containers:\\s*([A-Za-z0-9_\\- ,]+)", bundle_text):
    raw = m.group(1)
    for tok in re.split(r"[\\s,]+", raw.strip()):
        if tok and re.fullmatch(r"[A-Za-z0-9_\\-]{3,80}", tok):
            ids.add(tok)

# fallback if pattern changes
if not ids:
    ids = {"vsp-chart-topcwe","vsp-chart-topcves","vsp-chart-topcov","vsp-chart-trend","vsp-chart-sevbar"}

placeholders = "\\n".join([f'<div id="{html.escape(i)}"></div>' for i in sorted(ids)])
ph_block = f"""
<!-- VSP_STOP_JUMP_PLACEHOLDERS_V2 -->
<div id="vsp-stop-jump-placeholders" style="display:none">
{placeholders}
</div>
<!-- /VSP_STOP_JUMP_PLACEHOLDERS_V2 -->
"""

if "VSP_STOP_JUMP_PLACEHOLDERS_V2" not in s2:
    s2 = re.sub(r"(</body>)", ph_block + "\\n\\1", s2, flags=re.I)

tpl.write_text(s2, encoding="utf-8")
print("[OK] template patched: rid_autofix removed + cache bust + placeholders")
print("[OK] placeholders ids =", len(ids))
PY

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
echo "      Expect Console:"
echo "        - [VSP] rid_autofix DISABLED (noop force v2)"
echo "        - NO more '[STABLE_V1] missing containers' retry/jump"
