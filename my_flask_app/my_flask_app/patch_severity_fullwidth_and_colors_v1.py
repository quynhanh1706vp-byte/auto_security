import pathlib, re

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
data = path.read_text(encoding="utf-8")

# =========================
# 1) Kéo bar Severity buckets full chiều ngang
#    (thay w-40 thành w-full cho 4 thanh)
# =========================
data = data.replace(
    'class="w-40 h-1.5 bg-slate-900/90 rounded-full overflow-hidden"',
    'class="w-full h-1.5 bg-slate-900/90 rounded-full overflow-hidden"'
)

# Phòng trường hợp có dạng single-quote
data = data.replace(
    "class='w-40 h-1.5 bg-slate-900/90 rounded-full overflow-hidden'",
    "class='w-full h-1.5 bg-slate-900/90 rounded-full overflow-hidden'"
)

# =========================
# 2) Bổ sung override màu cho lime còn sót
# =========================
extra_css = """
    /* === Fix leftover lime → AATE green === */
    .bg-lime-500 {
      background-color: #10b981 !important;
      color: #022c22 !important;
      box-shadow: 0 10px 28px rgba(16,185,129,0.45);
      font-weight: 700;
    }
    .bg-lime-500:hover {
      filter: brightness(1.06);
      box-shadow: 0 14px 36px rgba(16,185,129,0.6);
    }
    .text-lime-400 {
      color: #6ee7b7 !important;
    }
"""

marker = "</style>"
idx = data.find(marker)
if idx != -1:
    data = data[:idx] + extra_css + "\n" + data[idx:]
else:
    print("[WARN] Không thấy </style> để chèn CSS màu bổ sung.")

path.write_text(data, encoding="utf-8")
print("[OK] Đã kéo bar Severity full width + unify màu xanh.")
