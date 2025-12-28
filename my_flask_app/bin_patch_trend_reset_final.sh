#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

pattern = r'<svg class="trend-svg" viewBox="0 0 100 36" preserveAspectRatio="none">[\s\S]*?</svg>'

replacement = r'''<svg class="trend-svg" viewBox="0 0 100 36" preserveAspectRatio="none">
                  <defs>
                    <linearGradient id="trendFillFinal" x1="0" x2="0" y1="0" y2="1">
                      <stop offset="0%" stop-color="#22c55e" stop-opacity="0.10" />
                      <stop offset="100%" stop-color="#22c55e" stop-opacity="0" />
                    </linearGradient>
                  </defs>

                  <!-- gridline ngang rất nhẹ -->
                  <g stroke="rgba(148,163,184,0.14)" stroke-width="0.22">
                    <line x1="14" y1="10"  x2="96" y2="10"  />
                    <line x1="14" y1="18.5" x2="96" y2="18.5" />
                    <line x1="14" y1="27"  x2="96" y2="27"  />
                  </g>

                  <!-- trục Y mềm, mảnh -->
                  <line x1="14" y1="7" x2="14" y2="30.5"
                        stroke="rgba(148,163,184,0.40)" stroke-width="0.35" />

                  <!-- tick + label nhỏ đồng bộ -->
                  <line x1="13.4" y1="27"  x2="14" y2="27"
                        stroke="rgba(148,163,184,0.65)" stroke-width="0.35" />
                  <line x1="13.4" y1="18.5" x2="14" y2="18.5"
                        stroke="rgba(148,163,184,0.65)" stroke-width="0.35" />
                  <line x1="13.4" y1="10"  x2="14" y2="10"
                        stroke="rgba(148,163,184,0.65)" stroke-width="0.35" />

                  <text x="5" y="28.2" font-size="1.8"
                        fill="rgba(148,163,184,0.80)">2.5k</text>
                  <text x="5" y="19.8" font-size="1.8"
                        fill="rgba(148,163,184,0.80)">3.5k</text>
                  <text x="5" y="11.4" font-size="1.8"
                        fill="rgba(148,163,184,0.80)">4.5k</text>

                  <!-- baseline X rất mảnh -->
                  <line x1="14" y1="30.5" x2="96" y2="30.5"
                        stroke="rgba(148,163,184,0.30)" stroke-width="0.30" />

                  <!-- area + line đẩy lên cao hơn để khung bớt trống -->
                  <path d="M14,23.5 L24,23.3 L36,22.8 L48,21
                           L60,18.8 L72,16.1 L84,14 L96,12.2
                           L96,30.5 L14,30.5 Z"
                        fill="url(#trendFillFinal)" />

                  <polyline points="14,23.5 24,23.3 36,22.8 48,21
                                    60,18.8 72,16.1 84,14 96,12.2"
                            stroke="#4ade80" stroke-width="0.8"
                            stroke-opacity="0.9" fill="none"
                            stroke-linejoin="round" stroke-linecap="round" />

                  <g fill="#4ade80">
                    <circle cx="14" cy="23.5" r="0.7" />
                    <circle cx="36" cy="22.8" r="0.7" />
                    <circle cx="60" cy="18.8" r="0.7" />
                    <circle cx="84" cy="14"   r="0.7" />
                    <circle cx="96" cy="12.2" r="0.8" />
                  </g>
                </svg>'''

new_html, n = re.subn(pattern, replacement, html)
print(f"[INFO] trend svg reset count: {n}")
if n:
    p.write_text(new_html, encoding="utf-8")
