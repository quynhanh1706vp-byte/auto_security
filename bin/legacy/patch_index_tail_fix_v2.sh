#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
T="$ROOT/templates/index.html"

echo "[PATCH] Target: $T"
cp "$T" "$T.bak_tailfix_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/index.html")
txt = p.read_text(encoding="utf-8")

marker = "// Tab switcher (giữ nguyên behavior cũ)"
idx = txt.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy marker Tab switcher, stop.")
    raise SystemExit(1)

head = txt[:idx]

tail = """<script>
  (function() {
    // Tab switcher (giữ nguyên behavior cũ) – bản clean
    const tabButtons = document.querySelectorAll('.vsp-tab-btn');
    const tabPanes   = document.querySelectorAll('.tab-pane');

    function switchTab(targetId) {
      tabButtons.forEach(b => b.classList.remove('active'));
      tabPanes.forEach(p => p.classList.remove('active'));

      const activeBtn = Array.from(tabButtons).find(b => b.dataset.tab === targetId);
      if (activeBtn) activeBtn.classList.add('active');

      const target = document.getElementById(targetId);
      if (target) {
        target.classList.add('active');
      } else {
        console.warn('[VSP_TAB] Không tìm thấy pane với id =', targetId);
      }
    }

    tabButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const targetId = btn.dataset.tab;
        if (targetId) switchTab(targetId);
      });
    });

    // Default tab: nếu có btn đang active thì giữ, không thì dùng btn đầu
    const activeBtn = Array.from(tabButtons).find(b => b.classList.contains('active'));
    const firstBtn  = tabButtons[0];
    const initial   = (activeBtn && activeBtn.dataset.tab) ||
                      (firstBtn && firstBtn.dataset.tab);
    if (initial) {
      switchTab(initial);
    }
  })();
</script>
</body>
</html>
"""

p.write_text(head + tail, encoding="utf-8")
print("[OK] Đã rebuild tail index.html, đóng đủ <script></script> / </body></html>.")
PY
