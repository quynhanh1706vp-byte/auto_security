#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_vsp5_bundle_${TS}"
echo "[BACKUP] ${WSGI}.bak_vsp5_bundle_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

if "/static/js/vsp_bundle_commercial_v2.js" in s and "/vsp5" in s:
    # vẫn patch, nhưng tránh double-insert ở đúng block /vsp5
    pass

# 1) tìm vị trí route /vsp5 trong file
pos = s.find('"/vsp5"')
if pos < 0:
    pos = s.find("'/vsp5'")
if pos < 0:
    pos = s.find("/vsp5")
if pos < 0:
    raise SystemExit("[ERR] cannot find /vsp5 in wsgi_vsp_ui_gateway.py")

# 2) lấy block function gần nhất (từ def trước pos đến def sau pos)
start = s.rfind("\ndef ", 0, pos)
if start < 0:
    start = 0
end = s.find("\ndef ", pos)
if end < 0:
    end = len(s)

blk = s[start:end]

# 3) nếu block đã có bundle include thì thôi
if "vsp_bundle_commercial_v2.js" in blk:
    print("[OK] /vsp5 block already has bundle include")
    raise SystemExit(0)

# 4) tìm line include gate_story trong block /vsp5
#    ưu tiên style:  <script src=\"...gate_story...?v=\" + asset_v + \"...\">
m = re.search(r'^[ \t]*".*?/static/js/vsp_dashboard_gate_story_v1\.js\?v=.*?asset_v.*?$',
              blk, flags=re.M)
if not m:
    # fallback: tìm bất kỳ dòng có gate_story
    m = re.search(r'^[ \t]*".*vsp_dashboard_gate_story_v1\.js.*?$',
                  blk, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot locate gate_story <script> line inside /vsp5 block")

gate_line = m.group(0)

# 5) tạo bundle line cùng style với gate_line
bundle_line = gate_line.replace("vsp_dashboard_gate_story_v1.js", "vsp_bundle_commercial_v2.js")

# nếu line bị replace nhưng không đổi (trường hợp lạ), tự build theo style phổ biến
if bundle_line == gate_line:
    if "+ asset_v +" in gate_line:
        indent = re.match(r'^(\s*)', gate_line).group(1)
        bundle_line = indent + '"  <script src=\\"/static/js/vsp_bundle_commercial_v2.js?v=" + asset_v + "\\"></script>",'
    else:
        indent = re.match(r'^(\s*)', gate_line).group(1)
        bundle_line = indent + '"  <script src=\\"/static/js/vsp_bundle_commercial_v2.js\\"></script>",'

# 6) insert bundle_line ngay trước gate_line
blk2 = blk[:m.start()] + bundle_line + "\n" + blk[m.start():]

s2 = s[:start] + blk2 + s[end:]

# 7) safety: không double insert nhiều nơi
if s2.count("vsp_bundle_commercial_v2.js") > s.count("vsp_bundle_commercial_v2.js") + 1:
    raise SystemExit("[ERR] patch would insert bundle more than once; aborting")

p.write_text(s2, encoding="utf-8")
print("[OK] inserted bundle include into /vsp5 block before gate_story")
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC"

echo "== verify /vsp5 contains bundle + gate_story =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_bundle_commercial_v2.js" | head -n 5 || { echo "[ERR] /vsp5 still missing bundle include"; exit 2; }
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_gate_story_v1.js" | head -n 5 || { echo "[ERR] /vsp5 missing gate_story include"; exit 2; }

echo "[DONE] OK. Now hard refresh: Ctrl+Shift+R  $BASE/vsp5"
