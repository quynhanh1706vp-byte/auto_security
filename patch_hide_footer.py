from pathlib import Path

p = Path("app.py")
text = p.read_text(encoding="utf-8")

css_old = """
    .footer {
      margin-top: 16px;
      font-size: 11px;
      color: var(--text-muted);
      display: flex;
      flex-wrap: wrap;
      gap: 6px 18px;
    }
"""

css_new = """
    .footer {
      display: none;
    }
"""

if css_old in text:
    text = text.replace(css_old, css_new)
    print("[OK] Đã ẩn footer (Data source / UI state / Tool config).")
else:
    print("[WARN] Không tìm thấy block .footer cũ, không sửa được.")

p.write_text(text, encoding="utf-8")
