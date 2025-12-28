#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
T="$ROOT/templates/index.html"

echo "[PATCH] Target: $T"
cp "$T" "$T.bak_dashboard_script_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/index.html")
txt = p.read_text(encoding="utf-8")

needle = "[VSP] Lỗi loadVspDashboard()"
i = txt.find(needle)
if i == -1:
    print("[ERR] Không tìm thấy chuỗi '[VSP] Lỗi loadVspDashboard()' trong index.html – stop.")
    raise SystemExit(1)

j = txt.rfind("<script", 0, i)
if j == -1:
    print("[ERR] Không tìm thấy '<script' trước đoạn loadVspDashboard – stop.")
    raise SystemExit(1)

head = txt[:j]

tail = '''
<script>
  (function() {
    async function loadVspDashboard() {
      try {
        const resp = await fetch("/api/vsp/dashboard_v3");
        if (!resp.ok) {
          console.error("[VSP] loadVspDashboard() HTTP error", resp.status);
          return;
        }
        const data = await resp.json();
        console.log("[VSP] loadVspDashboard() data:", data);

        // Nếu có hàm KPI binding thì gọi thử
        if (window.vspInitKpiBinding) {
          try {
            window.vspInitKpiBinding(data);
          } catch (e) {
            console.error("[VSP] Lỗi vspInitKpiBinding()", e);
          }
        }
      } catch (e) {
        console.error("[VSP] Lỗi loadVspDashboard()", e);
      }
    }

    // expose ra window cho các script khác / console dùng
    window.loadVspDashboard = loadVspDashboard;
  })();
</script>
</body>
</html>
'''

p.write_text(head + tail.lstrip("\\n"), encoding="utf-8")
print("[OK] Đã rebuild script loadVspDashboard() + tail index.html.")
PY
