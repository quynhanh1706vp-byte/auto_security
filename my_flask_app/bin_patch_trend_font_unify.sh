#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

# Chuẩn hoá 3 label 2.5k / 3.5k / 4.5k – font-size nhỏ, đồng bộ
html = re.sub(
    r'<text[^>]*>2\.5k</text>',
    '<text x="5" y="28.2" font-size="2.1" '
    'fill="rgba(148,163,184,0.82)">2.5k</text>',
    html,
)

html = re.sub(
    r'<text[^>]*>3\.5k</text>',
    '<text x="5" y="19.8" font-size="2.1" '
    'fill="rgba(148,163,184,0.82)">3.5k</text>',
    html,
)

html = re.sub(
    r'<text[^>]*>4\.5k</text>',
    '<text x="5" y="11.4" font-size="2.1" '
    'fill="rgba(148,163,184,0.82)">4.5k</text>',
    html,
)

p.write_text(html, encoding="utf-8")
print("[INFO] Y-axis label font normalized.")
