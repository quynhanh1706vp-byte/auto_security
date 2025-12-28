#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

# Thay toàn bộ SVG của trend (viewBox 0 0 100 36)
pattern = r'<svg class="trend-svg" viewBox="0 0 100 36" preserveAspectRatio="none">[\s\S]*?</svg>'

replacement = r'''<svg class="trend-svg" viewBox="0 0 100 36" preserveAspectRatio="none">
                  <defs>
                    <linearGradient id="trendFillFinal" x1="0" x2="0" y1="0" y2="1">
                      <stop offset="0%" stop-color="#22c55e" stop-opacity="0.10" />
                      <stop offset="100%" stop-color="#22c55e" stop-opacity="0" />
                    </linearGradient>
                  </defs>

                  <!-- gridline ngang rất nhẹ, không chạm mép trái -->
                  <g stroke="rgba(148,163,184,0.14)" stroke-width="0.22">
                    <line x1="14" y1="10"  x2="96" y2="10"  />
                    <line x1="14" y1="18.5" x2="96" y2="18.5" />
                    <line x1="14" y1="27"  x2="96" y2="27"  />
                  </g>

                  <!-- trục Y mềm, mảnh -->
                  <line x1="14" y1="7" x2="14" y2="30.5"
                        stroke="rgba(148,163,184,0.40)" stroke-width="0.35" />

                  <!-- tick nhỏ + label nhỏ -->
                  <line x1="13.4" y1="27"  x2="14" y2="27"
                        stroke="rgba(148,163,184,0.65)" stroke-width="0.35" />
                  <line x1="13.4" y1="18.5" x2="14" y2="18.5"
                        stroke="rgba(148,163,184,0.65)" stroke-width="0.35" />
                  <line x1="13.4" y1="10"  x2="14" y2="10"
                        stroke="rgba(148,163,184,0.65)" stroke-width="0.35" />

                  <text x="5" y="28.2" font-size="3" fill="rgba(148,163,184,0.85)">2.5k</text>
                  <text x="5" y="19.8" font-size="3" fill="rgba(148,163,184,0.85)">3.5k</text>
                  <text x="5" y="11.4" font-size="3" fill="rgba(148,163,184,0.85)">4.5k</text>

                  <!-- đường baseline (X) rất mảnh -->
                  <line x1="14" y1="30.5" x2="96" y2="30.5"
                        stroke="rgba(148,163,184,0.30)" stroke-width="0.30" />

                  <!-- area dưới đường – mềm -->
                  <path d="M14,26.5 L24,26.3 L36,25.8 L48,24 L60,21.8 L72,19.1 L84,17 L96,15.2 L96,30.5 L14,30.5 Z"
                        fill="url(#trendFillFinal)" />

                  <!-- đường trend – mảnh, màu dịu -->
                  <polyline points="14,26.5 24,26.3 36,25.8 48,24 60,21.8 72,19.1 84,17 96,15.2"
                            stroke="#4ade80" stroke-width="0.8" stroke-opacity="0.9"
                            fill="none" stroke-linejoin="round" stroke-linecap="round" />

                  <!-- chấm nhỏ trên đường -->
                  <g fill="#4ade80">
                    <circle cx="14" cy="26.5" r="0.7" />
                    <circle cx="36" cy="25.8" r="0.7" />
                    <circle cx="60" cy="21.8" r="0.7" />
                    <circle cx="84" cy="17"   r="0.7" />
                    <circle cx="96" cy="15.2" r="0.8" />
                  </g>
                </svg>'''

new_html, n = re.subn(pattern, replacement, html)
print(f"[INFO] trend svg (final) replaced: {n}")
if n:
    p.write_text(new_html, encoding="utf-8")
