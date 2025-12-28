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

marker = "SB-RUN-FORM-V1"
if marker in data:
    print("[INFO] SB-RUN-FORM đã tồn tại, không sửa.")
    raise SystemExit(0)

# Tìm dòng chứa chữ SECURITY SCAN
needle = "SECURITY SCAN"
pos = data.find(needle)
if pos == -1:
    print("[ERR] Không tìm thấy chuỗi 'SECURITY SCAN' trong templates/index.html")
    raise SystemExit(1)

# chèn ngay SAU dòng đó
line_end = data.find("\n", pos)
if line_end == -1:
    line_end = len(data)

snippet = """
      <!-- SB-RUN-FORM-V1: Khung nhập thông tin RUN -->
      <div class="sb-run-form"
           style="margin:16px 0 18px 0;padding:14px 18px;border-radius:18px;
                  background:rgba(15,23,42,0.96);border:1px solid rgba(148,163,184,0.45);
                  display:flex;flex-wrap:wrap;gap:12px;align-items:flex-end;">
        <div style="flex:2;min-width:260px;">
          <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;
                      opacity:.7;margin-bottom:4px;">
            Target URL (optional)
          </div>
          <input id="sb_target_url"
                 placeholder="https://app.example.com (for report only)"
                 style="width:100%;border-radius:999px;background:rgba(15,23,42,0.9);
                        border:1px solid rgba(148,163,184,0.7);padding:8px 14px;
                        font-size:13px;color:#e5e7eb;outline:none;">
        </div>

        <div style="flex:2;min-width:260px;">
          <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;
                      opacity:.7;margin-bottom:4px;">
            SRC folder
          </div>
          <input id="sb_src_folder"
                 placeholder="/home/test/Data/Khach_1"
                 style="width:100%;border-radius:999px;background:rgba(15,23,42,0.9);
                        border:1px solid rgba(148,163,184,0.7);padding:8px 14px;
                        font-size:13px;color:#e5e7eb;outline:none;">
        </div>

        <div style="min-width:140px;">
          <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;
                      opacity:.7;margin-bottom:4px;">
            Profile
          </div>
          <select id="sb_profile"
                  style="width:100%;border-radius:999px;background:rgba(15,23,42,0.9);
                         border:1px solid rgba(148,163,184,0.7);padding:8px 14px;
                         font-size:13px;color:#e5e7eb;outline:none;">
            <option value="aggr">Aggressive</option>
            <option value="fast">Fast</option>
          </select>
        </div>

        <div style="min-width:140px;">
          <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;
                      opacity:.7;margin-bottom:4px;">
            Mode
          </div>
          <select id="sb_mode"
                  style="width:100%;border-radius:999px;background:rgba(15,23,42,0.9);
                         border:1px solid rgba(148,163,184,0.7);padding:8px 14px;
                         font-size:13px;color:#e5e7eb;outline:none;">
            <option value="Offline">Offline</option>
            <option value="Online">Online</option>
            <option value="CI/CD">CI/CD</option>
          </select>
        </div>

        <div style="min-width:210px;max-width:260px;display:flex;flex-direction:column;gap:6px;">
          <button id="sb_run_btn" type="button"
                  style="border:none;border-radius:999px;padding:10px 16px;
                         font-size:13px;font-weight:600;cursor:pointer;
                         background:linear-gradient(135deg,#22c55e,#4ade80);
                         color:#020617;box-shadow:0 0 0 1px rgba(34,197,94,0.35),
                         0 10px 26px rgba(34,197,94,0.35);">
            Lưu cấu hình RUN (UI)
          </button>
          <div style="font-size:11px;line-height:1.4;opacity:.72;">
            Khung này dùng để <b>nhập và lưu lại cấu hình RUN</b> trên UI
            (TARGET URL, SRC folder, profile, mode). Việc chạy scan thực tế bạn
            vẫn có thể dùng script CLI như hiện tại.
          </div>
        </div>
      </div>
"""

new_data = data[:line_end+1] + snippet + data[line_end+1:]

# Thêm JS lưu/restore localStorage (nếu chưa có)
js_marker = "SB-RUN-FORM-V1-JS"
if js_marker not in new_data:
    script = f"""
  <!-- {js_marker} -->
  <script>
    (function() {{
      const KEY = 'sb_run_form_v1';
      function loadCfg() {{
        try {{
          const raw = window.localStorage.getItem(KEY);
          if (!raw) return;
          const cfg = JSON.parse(raw);
          if (cfg.target) document.getElementById('sb_target_url').value = cfg.target;
          if (cfg.src) document.getElementById('sb_src_folder').value = cfg.src;
          if (cfg.profile) document.getElementById('sb_profile').value = cfg.profile;
          if (cfg.mode) document.getElementById('sb_mode').value = cfg.mode;
        }} catch(e) {{
          console.warn('[SB-RUN-FORM]', 'load error', e);
        }}
      }}
      function saveCfg() {{
        try {{
          const cfg = {{
            target: document.getElementById('sb_target_url').value || '',
            src: document.getElementById('sb_src_folder').value || '',
            profile: document.getElementById('sb_profile').value || '',
            mode: document.getElementById('sb_mode').value || ''
          }};
          window.localStorage.setItem(KEY, JSON.stringify(cfg));
          console.log('[SB-RUN-FORM]', 'saved', cfg);
          const btn = document.getElementById('sb_run_btn');
          if (btn) {{
            const oldTxt = btn.textContent;
            btn.textContent = 'Đã lưu cấu hình RUN';
            setTimeout(() => btn.textContent = oldTxt, 2000);
          }}
        }} catch(e) {{
          console.warn('[SB-RUN-FORM]', 'save error', e);
        }}
      }}
      document.addEventListener('DOMContentLoaded', function() {{
        try {{
          loadCfg();
          const btn = document.getElementById('sb_run_btn');
          if (btn) btn.addEventListener('click', saveCfg);
        }} catch(e) {{
          console.warn('[SB-RUN-FORM]', 'init error', e);
        }}
      }});
    }})();
  </script>
"""
    pos_body = new_data.rfind("</body>")
    if pos_body == -1:
        print("[ERR] Không thấy </body> để chèn JS.")
        raise SystemExit(1)
    new_data = new_data[:pos_body] + script + new_data[pos_body:]
    print("[OK] Đã chèn JS SB-RUN-FORM-V1.")

path.write_text(new_data, encoding="utf-8")
print("[DONE] Đã chèn khung nhập thông tin RUN.")
PY
