#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

# A. Giảm tiếp font-size cho 2.5k / 3.5k / 4.5k
html = re.sub(
    r'<text[^>]*>2\.5k</text>',
    '<text x="5" y="28.2" font-size="1.8" '
    'fill="rgba(148,163,184,0.8)">2.5k</text>',
    html,
)
html = re.sub(
    r'<text[^>]*>3\.5k</text>',
    '<text x="5" y="19.8" font-size="1.8" '
    'fill="rgba(148,163,184,0.8)">3.5k</text>',
    html,
)
html = re.sub(
    r'<text[^>]*>4\.5k</text>',
    '<text x="5" y="11.4" font-size="1.8" '
    'fill="rgba(148,163,184,0.8)">4.5k</text>',
    html,
)

# B. Đẩy đường trend + area lên cao hơn để bớt trống
# (giảm các giá trị y ~ 3 đơn vị)
html = html.replace(
    'M14,26.5 L24,26.3 L36,25.8 L48,24 L60,21.8 L72,19.1 L84,17 L96,15.2 L96,30.5 L14,30.5 Z',
    'M14,23.5 L24,23.3 L36,22.8 L48,21 L60,18.8 L72,16.1 L84,14 L96,12.2 L96,30.5 L14,30.5 Z',
)

html = html.replace(
    '14,26.5 24,26.3 36,25.8 48,24 60,21.8 72,19.1 84,17 96,15.2',
    '14,23.5 24,23.3 36,22.8 48,21 60,18.8 72,16.1 84,14 96,12.2',
)

html = html.replace('circle cx="14" cy="26.5"', 'circle cx="14" cy="23.5"')
html = html.replace('circle cx="36" cy="25.8"', 'circle cx="36" cy="22.8"')
html = html.replace('circle cx="60" cy="21.8"', 'circle cx="60" cy="18.8"')
html = html.replace('circle cx="84" cy="17"',   'circle cx="84" cy="14"')
html = html.replace('circle cx="96" cy="15.2"', 'circle cx="96" cy="12.2"')

p.write_text(html, encoding="utf-8")
print("[INFO] Trend labels shrinked & polyline lifted.")
