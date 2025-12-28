from pathlib import Path

p = Path("app.py")
text = p.read_text(encoding="utf-8")

css_old = """
    .header-right {
      font-size: 11px;
      text-align: right;
      color: var(--text-muted);
    }
    .header-right code {
      font-size: 11px;
      color: #e5e7eb;
    }
"""

css_new = """
    .header-right {
      display: none;
    }
"""

if css_old in text:
    text = text.replace(css_old, css_new)
    print("[OK] Đã ẩn block ROOT/RUN/SRC ở góc phải trên.")
else:
    # fallback: chèn thêm rule ẩn .header-right nếu không match đúng block cũ
    marker = ".header-right {"
    if marker not in text:
        text = text.replace("body {", "body {") + "\n    .header-right { display:none; }\n"
    print("[WARN] Không tìm thấy block .header-right cũ, đã thêm rule display:none.")

p.write_text(text, encoding="utf-8")
