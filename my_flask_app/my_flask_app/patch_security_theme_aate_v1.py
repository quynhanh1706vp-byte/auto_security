import pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
data = path.read_text(encoding="utf-8")

# 1) Đổi các màu cứng trong <style>
replacements = {
    "#0f172a": "#021a16",   # nền body -> xanh đậm
    "#1e293b": "#041f1a",   # card bg
    "#334155": "#064e3b",   # card border
    "#a3e635": "#10b981",   # nút Run scan -> xanh ngọc
    "#22c55e": "#10b981",   # nút Save -> cùng màu
    "#1e3a1e": "#022c22",   # tile total bg
    "#65a30d": "#16a34a",   # tile total border
    "#450a0a": "rgba(220,38,38,0.16)",   # critical bg mềm lại
    "#431407": "rgba(234,88,12,0.16)",   # high bg
    "#422006": "rgba(217,119,6,0.16)",   # medium bg
    "#172554": "rgba(14,165,233,0.16)",  # low bg
    "#365314": "#10b981",   # active-menu / tab-active bg
    "#bef264": "#022c22",   # active-menu text -> xanh đậm (giống AATE)
}

for old, new in replacements.items():
    data = data.replace(old, new)

# 2) Thêm CSS override cho Tailwind slate -> green
extra_css = """
    /* === AATE-style green theme overrides === */
    body {
      background: radial-gradient(circle at top, #063c34 0, #021a16 45%, #020712 100%);
      color: #e0fff5;
    }
    .card {
      background: radial-gradient(circle at top left, #063c34 0, #041f1a 40%, #020e0b 100%);
      border-color: #064e3b;
    }
    .btn-run,
    .btn-save {
      background: #10b981;
      color: #022c22;
      font-weight: 800;
      box-shadow: 0 12px 30px rgba(16,185,129,0.35);
    }
    .btn-run:hover,
    .btn-save:hover {
      filter: brightness(1.08);
      box-shadow: 0 16px 40px rgba(16,185,129,0.5);
    }
    .active-menu,
    .tab-active {
      background: #10b981 !important;
      color: #022c22 !important;
      box-shadow: 0 0 24px rgba(16,185,129,0.4);
    }
    /* Override các lớp slate mặc định để sidebar + viền cùng theme */
    .bg-slate-900 { background-color: #020f0c !important; }
    .bg-slate-800 { background-color: #041c17 !important; }
    .border-slate-800 { border-color: #064e3b !important; }
    .border-slate-700 { border-color: #065f46 !important; }
    .text-slate-400 { color: #a7f3d0 !important; }
"""

marker = "</style>"
idx = data.find(marker)
if idx != -1:
    data = data[:idx] + extra_css + "\n" + data[idx:]
else:
    print("[WARN] Không tìm thấy </style>, không chèn được extra CSS.")

path.write_text(data, encoding="utf-8")
print("[OK] Đã patch theme AATE cho SECURITY_BUNDLE_FULL_5_PAGES.html.")
