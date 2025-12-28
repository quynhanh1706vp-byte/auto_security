#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need grep; need sed; need date

TPL=""
# ưu tiên file có /vsp5
TPL="$(grep -RIl "/vsp5" templates 2>/dev/null | head -n1 || true)"
# fallback: file có "Runs & Reports"
[ -n "$TPL" ] || TPL="$(grep -RIl "Runs & Reports" templates 2>/dev/null | head -n1 || true)"
# fallback: file có "VersaSecure Platform" (thường là dashboard commercial)
[ -n "$TPL" ] || TPL="$(grep -RIl "VersaSecure Platform" templates 2>/dev/null | head -n1 || true)"

[ -n "$TPL" ] || { echo "[ERR] cannot find vsp5 template under templates/"; exit 2; }
echo "[TPL]=$TPL"

JS="/static/js/vsp_runs_tab_resolved_v1.js"
[ -f "static/js/vsp_runs_tab_resolved_v1.js" ] || { echo "[ERR] missing static/js/vsp_runs_tab_resolved_v1.js"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "${TPL}.bak_include_runs_enh_${TS}"
echo "[BACKUP] ${TPL}.bak_include_runs_enh_${TS}"

MARK="VSP5_INCLUDE_RUNS_ENHANCER_P0_V1"
if grep -q "$MARK" "$TPL"; then
  echo "[OK] already injected marker"
else
  # inject right before </body>
  sed -i "s#</body>#\n<!-- ${MARK} -->\n<script defer src=\"${JS}?v=${TS}\"></script>\n</body>#I" "$TPL"
  echo "[OK] injected <script defer src=${JS}?v=${TS}> into $TPL"
fi

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== smoke /vsp5 =="
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,15p'
