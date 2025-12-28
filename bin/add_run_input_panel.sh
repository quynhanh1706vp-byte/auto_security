#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")

marker = "SB-RUN-INPUT-PANEL"
if marker in data:
    print("[INFO] Panel run input đã tồn tại, không sửa.")
    raise SystemExit(0)

snippet = """
      <!-- SB-RUN-INPUT-PANEL: simple run info form -->
      <section class="sb-run-input-panel"
               style="margin-bottom:24px;border-radius:18px;background:rgba(5,8,16,0.95);
                      padding:20px 24px;border:1px solid rgba(255,255,255,0.05);">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:18px;flex-wrap:wrap;">
          <div style="min-width:220px;flex:1;">
            <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;opacity:.65;margin-bottom:4px;">
              Target URL (optional)
            </div>
            <input id="sb_run_target_url"
                   placeholder="https://app.example.com (for report only)"
                   style="width:100%;border-radius:999px;background:rgba(15,23,42,0.9);
                          border:1px solid rgba(148,163,184,0.45);padding:8px 14px;
                          font-size:13px;color:#e5e7eb;outline:none;">
          </div>

          <div style="min-width:260px;flex:1;">
            <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;opacity:.65;margin-bottom:4px;">
              SRC folder
            </div>
            <input id="sb_run_src_folder"
                   placeholder="/home/test/Data/Khach_1"
                   style="width:100%;border-radius:999px;background:rgba(15,23,42,0.9);
                          border:1px solid rgba(148,163,184,0.45);padding:8px 14px;
                          font-size:13px;color:#e5e7eb;outline:none;">
          </div>

          <div style="min-width:140px;">
            <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;opacity:.65;margin-bottom:4px;">
              Profile
            </div>
            <select id="sb_run_profile"
                    style="width:100%;border-radius:999px;background:rgba(15,23,42,0.9);
                           border:1px solid rgba(148,163,184,0.45);padding:8px 14px;
                           font-size:13px;color:#e5e7eb;outline:none;">
              <option value="aggr">Aggressive</option>
              <option value="fast">Fast</option>
            </select>
          </div>

          <div style="min-width:140px;">
            <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;opacity:.65;margin-bottom:4px;">
              Mode
            </div>
            <select id="sb_run_mode"
                    style="width:100%;border-radius:999px;background:rgba(15,23,42,0.9);
                           border:1px solid rgba(148,163,184,0.45);padding:8px 14px;
                           font-size:13px;color:#e5e7eb;outline:none;">
              <option value="Offline">Offline</option>
              <option value="Online">Online</option>
              <option value="CI/CD">CI/CD</option>
            </select>
          </div>

          <div style="min-width:220px;max-width:260px;display:flex;flex-direction:column;gap:6px;">
            <button id="sb_run_save_btn" type="button"
                    style="border:none;border-radius:999px;padding:10px 16px;
                           font-size:13px;font-weight:600;cursor:pointer;
                           background:linear-gradient(135deg,#22c55e,#4ade80);
                           color:#020617;box-shadow:0 0 0 1px rgba(34,197,94,0.35),
                           0 12px 30px rgba(34,197,94,0.35);">
              Lưu cấu hình hiển thị
            </button>
            <div style="font-size:11px;line-height:1.4;opacity:.75;">
              Panel này chỉ dùng để <b>ghi nhớ thông tin RUN</b> trên UI
              (TARGET URL, SRC, profile, mode). Việc chạy scan thực tế bạn vẫn dùng
              script CLI của SECURITY_BUNDLE.
            </div>
          </div>
        </div>
      </section>
"""

# Chèn panel ngay trước DASHBOARD chính (thường bắt đầu bằng <section class="sb-dashboard">)
insert_pos = data.find('<section class="sb-dashboard"')
if insert_pos == -1:
    # fallback: chèn ngay trước </main>
    end_main = data.find("</main>")
    if end_main == -1:
        print("[ERR] Không tìm thấy sb-dashboard hoặc </main> để chèn panel.")
        raise SystemExit(1)
    new_data = data[:end_main] + snippet + data[end_main:]
    print("[WARN] Không thấy sb-dashboard, đã chèn panel trước </main>.")
else:
    new_data = data[:insert_pos] + snippet + data[insert_pos:]
    print("[OK] Đã chèn panel run input trước sb-dashboard.")

# Thêm JS nhỏ ở cuối file (trước </body>) để lưu/restore localStorage
js_marker = "SB-RUN-INPUT-PANEL-JS"
if js_marker not in new_data:
    script_block = f"""
  <!-- {js_marker} -->
  <script>
    (function() {{
      const KEY = 'sb_run_input_panel_v1';
      function load() {{
        try {{
          const raw = window.localStorage.getItem(KEY);
          if (!raw) return;
          const cfg = JSON.parse(raw);
          if (cfg.target) document.getElementById('sb_run_target_url').value = cfg.target;
          if (cfg.src) document.getElementById('sb_run_src_folder').value = cfg.src;
          if (cfg.profile) document.getElementById('sb_run_profile').value = cfg.profile;
          if (cfg.mode) document.getElementById('sb_run_mode').value = cfg.mode;
        }} catch (e) {{
          console.warn('[SB-RUN]', 'Load config error', e);
        }}
      }}
      function save() {{
        try {{
          const cfg = {{
            target: document.getElementById('sb_run_target_url').value || '',
            src: document.getElementById('sb_run_src_folder').value || '',
            profile: document.getElementById('sb_run_profile').value || '',
            mode: document.getElementById('sb_run_mode').value || ''
          }};
          window.localStorage.setItem(KEY, JSON.stringify(cfg));
          console.log('[SB-RUN]', 'Saved config', cfg);
          const btn = document.getElementById('sb_run_save_btn');
          if (btn) {{
            const old = btn.textContent;
            btn.textContent = 'Đã lưu cấu hình';
            setTimeout(() => {{ btn.textContent = old; }}, 2000);
          }}
        }} catch (e) {{
          console.warn('[SB-RUN]', 'Save config error', e);
        }}
      }}
      document.addEventListener('DOMContentLoaded', function() {{
        try {{
          load();
          var btn = document.getElementById('sb_run_save_btn');
          if (btn) btn.addEventListener('click', save);
        }} catch (e) {{
          console.warn('[SB-RUN]', 'Init error', e);
        }}
      }});
    }})();
  </script>
"""
    pos_body = new_data.rfind("</body>")
    if pos_body == -1:
        print("[ERR] Không tìm thấy </body> để chèn script.")
        raise SystemExit(1)
    new_data = new_data[:pos_body] + script_block + new_data[pos_body:]
    print("[OK] Đã chèn JS lưu cấu hình run input.")
else:
    print("[INFO] JS panel run input đã tồn tại, không thêm.")

path.write_text(new_data, encoding="utf-8")
PY
