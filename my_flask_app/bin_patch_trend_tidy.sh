#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

# A. Giảm chiều cao trend-area + padding cho bớt trống
css_pattern = r"""\.trend-area \{[\s\S]*?}"""
css_replacement = r""".trend-area {
      position: relative;
      flex: 1;
      min-height: 70px;
      height: 70px;
      border-radius: 12px;
      background: #020617;
      padding: 4px 10px 12px;
      overflow: hidden;
      border: 1px solid rgba(30, 64, 175, 0.5);
    }"""
html, n_css = re.subn(css_pattern, css_replacement, html)
print(f"[INFO] patched .trend-area CSS: {n_css}")

# B. Giảm size chữ trục Y để đồng bộ với label trục X / card khác
html = html.replace(
    '<text x="5" y="28.2" font-size="3" fill="rgba(148,163,184,0.85)">2.5k</text>',
    '<text x="5" y="28.2" font-size="2.6" fill="rgba(148,163,184,0.85)">2.5k</text>',
)
html = html.replace(
    '<text x="5" y="19.8" font-size="3" fill="rgba(148,163,184,0.85)">3.5k</text>',
    '<text x="5" y="19.8" font-size="2.6" fill="rgba(148,163,184,0.85)">3.5k</text>',
)
html = html.replace(
    '<text x="5" y="11.4" font-size="3" fill="rgba(148,163,184,0.85)">4.5k</text>',
    '<text x="5" y="11.4" font-size="2.6" fill="rgba(148,163,184,0.85)">4.5k</text>',
)

p.write_text(html, encoding="utf-8")
print("[INFO] trend labels + height updated.")
