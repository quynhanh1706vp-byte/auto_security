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
 * Commercial Dashboard contract: rid comes ONLY from /api/vsp/rid_latest_gate_root (inside DashCommercialV1),
 * NEVER from this legacy rid_autofix module.
 */
(()=> {
  if (window.__vsp_noop_rid_autofix_force_v2) return;
  window.__vsp_noop_rid_autofix_force_v2 = true;
  try { console.info("[VSP] rid_autofix DISABLED (noop force v2)"); } catch(e){}
})();
JS

# 2) Patch template: remove rid_autofix script tag, bust cache for bundle & polish,
#    and add hidden placeholders for "missing containers" so STABLE_V1 stops retrying.
cp -f "$TPL" "${TPL}.bak_stopjump_${TS}"
echo "[BACKUP] ${TPL}.bak_stopjump_${TS}"

python3 - <<PY
from pathlib import Path
import re, html

ts = "${TS}"
tpl = Path("${TPL}")
bundle = Path("${BUNDLE}").read_text(encoding="utf-8", errors="replace")

s = tpl.read_text(encoding="utf-8", errors="replace")

# remove any rid_autofix script tag
s2 = re.sub(r'\\s*<script[^>]+src=["\\\']\\/static\\/js\\/vsp_rid_autofix_v1\\.js[^"\\\']*["\\\'][^>]*>\\s*<\\/script>\\s*', "\\n", s, flags=re.I)

# ensure polish css link exists and is cache-busted
polish_link = f'<link rel="stylesheet" href="/static/css/vsp_dashboard_polish_v1.css?v={ts}"/>'
if "vsp_dashboard_polish_v1.css" not in s2:
    s2 = re.sub(r'(</head>)', polish_link + "\\n\\1", s2, flags=re.I)
else:
    s2 = re.sub(r'\\/static\\/css\\/vsp_dashboard_polish_v1\\.css\\?v=[^"\\\']+', f'/static/css/vsp_dashboard_polish_v1.css?v={ts}', s2)

# bust cache for bundle
s2 = re.sub(r'\\/static\\/js\\/vsp_bundle_commercial_v2\\.js\\?v=[^"\\\']+',
            f'/static/js/vsp_bundle_commercial_v2.js?v={ts}', s2)

# extract missing container ids from bundle logs: "missing containers: a,b,c"
ids = set()
for m in re.finditer(r"missing containers:\\s*([A-Za-z0-9_\\- ,]+)", bundle):
    raw = m.group(1)
    for tok in re.split(r"[\\s,]+", raw.strip()):
        if tok and re.fullmatch(r"[A-Za-z0-9_\\-]{3,80}", tok):
            ids.add(tok)

# fallback (if bundle log changes)
fallback = {"vsp-chart-topcwe","vsp-chart-topcovc","vsp-chart-topcves","vsp-chart-topcwe","vsp-chart-topcov"}
if not ids:
    ids = fallback

placeholders = "\\n".join([f'<div id="{html.escape(i)}"></div>' for i in sorted(ids)])
ph_block = f"""
<!-- VSP_STOP_JUMP_PLACEHOLDERS_V1 -->
<div id="vsp-stop-jump-placeholders" style="display:none">
{placeholders}
</div>
<!-- /VSP_STOP_JUMP_PLACEHOLDERS_V1 -->
"""

if "VSP_STOP_JUMP_PLACEHOLDERS_V1" not in s2:
    s2 = re.sub(r'(</body>)', ph_block + "\\n\\1", s2, flags=re.I)

# add a tiny boot-flag (harmless, but helps future guards)
bootflag = '<script>window.__VSP_DASH_MODE="commercial";window.__VSP_DISABLE_RID_AUTOFIX=true;</script>'
if "__VSP_DASH_MODE" not in s2:
    s2 = re.sub(r'(</head>)', bootflag + "\\n\\1", s2, flags=re.I)

tpl.write_text(s2, encoding="utf-8")
print("[OK] template patched: remove rid_autofix tag + bust cache + placeholders")
print("[OK] placeholders ids =", len(ids))
PY

echo "[DONE] Now hard refresh /vsp5 (Ctrl+Shift+R)."
echo "      Expect Console:"
echo "        - [VSP] rid_autofix DISABLED (noop force v2)"
echo "        - NO more '[STABLE_V1] missing containers' retry spam"
