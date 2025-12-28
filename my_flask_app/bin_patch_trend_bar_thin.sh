#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

# --- A. Làm cột bar mảnh hơn ---
css_pattern = r"""\.bar-wrapper \{[\s\S]+?\.bar-label-row \{"""
css_replacement = r""".bar-wrapper {
      flex: 1;
      min-height: 140px;
      display: flex;
      align-items: flex-end;
      justify-content: space-around;  /* giãn đều, không dính sát nhau */
      gap: 6px;
      padding: 6px 4px 4px;
    }

    .bar,
    .bar-muted {
      flex: 0 0 12%;                  /* cột mảnh hơn */
      max-width: 40px;
      border-radius: 8px 8px 0 0;
    }

    .bar {
      background: linear-gradient(180deg, #facc15, #b45309);
      box-shadow: none;
      height: 120px;
    }

    .bar-muted {
      height: 28px;
      background: linear-gradient(180deg,
                  rgba(148, 163, 184, 0.5),
                  rgba(15, 23, 42, 1));
      box-shadow: none;
    }

    .bar-label-row {
      display: flex;
      justify-content: space-between;
      font-size: 10px;
      color: var(--text-muted);
      margin-top: 4px;
    }
"""
html, n1 = re.subn(css_pattern, css_replacement, html)
print(f"[INFO] patched bar CSS blocks: {n1}")

# --- B. Thu nhỏ chữ trục Y của trend chart ---
html = re.sub(
    r'<text x="4" y="34" font-size="7"',
    '<text x="2" y="34" font-size="4"',
    html,
)
html = re.sub(
    r'<text x="4" y="26" font-size="7"',
    '<text x="2" y="26" font-size="4"',
    html,
)
html = re.sub(
    r'<text x="4" y="18" font-size="7"',
    '<text x="2" y="18" font-size="4"',
    html,
)

p.write_text(html, encoding="utf-8")
print("[INFO] trend Y-axis labels made smaller.")
