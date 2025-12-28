#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

# Thay toàn bộ thẻ <svg ...>...</svg> của trend chart
pattern = r'<svg class="trend-svg" viewBox="0 0 100 36" preserveAspectRatio="none">[\s\S]*?</svg>'

replacement = r'''<svg class="trend-svg" viewBox="0 0 100 36" preserveAspectRatio="none">
                  <defs>
                    <linearGradient id="trendFillSoft" x1="0" x2="0" y1="0" y2="1">
                      <stop offset="0%" stop-color="#22c55e" stop-opacity="0.14" />
                      <stop offset="100%" stop-color="#22c55e" stop-opacity="0" />
                    </linearGradient>
                  </defs>

                  <!-- gridline ngang rất nhẹ -->
                  <g stroke="rgba(148,163,184,0.18)" stroke-width="0.25">
                    <line x1="12" y1="10"  x2="96" y2="10"  />
                    <line x1="12" y1="18.5" x2="96" y2="18.5" />
                    <line x1="12" y1="27"  x2="96" y2="27"  />
                  </g>

                  <!-- trục Y rất mảnh, hơi nhạt -->
                  <line x1="12" y1="7" x2="12" y2="30.5"
                        stroke="rgba(148,163,184,0.45)" stroke-width="0.45" />

                  <!-- tick + label nhỏ trên trục Y -->
                  <line x1="11.2" y1="27"  x2="12" y2="27"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.4" />
                  <line x1="11.2" y1="18.5" x2="12" y2="18.5"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.4" />
                  <line x1="11.2" y1="10"  x2="12" y2="10"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.4" />

                  <text x="3" y="28.2" font-size="3.2" fill="rgba(148,163,184,0.85)">2.5k</text>
                  <text x="3" y="19.8" font-size="3.2" fill="rgba(148,163,184,0.85)">3.5k</text>
                  <text x="3" y="11.4" font-size="3.2" fill="rgba(148,163,184,0.85)">4.5k</text>

                  <!-- area dưới đường – mềm, trong suốt -->
                  <path d="M12,26.5 L22,26.3 L34,25.8 L46,24 L58,21.8 L70,19.1 L82,17 L94,15.2 L94,30.5 L12,30.5 Z"
                        fill="url(#trendFillSoft)" />

                  <!-- đường trend mảnh, không sáng chói -->
                  <polyline points="12,26.5 22,26.3 34,25.8 46,24 58,21.8 70,19.1 82,17 94,15.2"
                            stroke="#4ade80" stroke-width="0.8" stroke-opacity="0.9"
                            fill="none" stroke-linejoin="round" stroke-linecap="round" />

                  <!-- chấm nhỏ trên đường -->
                  <g fill="#4ade80">
                    <circle cx="12" cy="26.5" r="0.7" />
                    <circle cx="34" cy="25.8" r="0.7" />
                    <circle cx="58" cy="21.8" r="0.7" />
                    <circle cx="82" cy="17"   r="0.7" />
                    <circle cx="94" cy="15.2" r="0.8" />
                  </g>
                </svg>'''

new_html, n = re.subn(pattern, replacement, html)
print(f"[INFO] trend svg replaced: {n}")
if n:
    p.write_text(new_html, encoding="utf-8")
