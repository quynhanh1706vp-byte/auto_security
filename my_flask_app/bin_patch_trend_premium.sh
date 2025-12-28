#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

pattern = r'<div class="trend-area">[\s\S]*?</div>\s*</div>\s*</div>\s*<!-- RIGHT -->'

replacement = r'''<div class="trend-area">
                <svg class="trend-svg" viewBox="0 0 100 36" preserveAspectRatio="none">
                  <defs>
                    <linearGradient id="trendFill" x1="0" x2="0" y1="0" y2="1">
                      <stop offset="0%" stop-color="#22c55e" stop-opacity="0.18" />
                      <stop offset="100%" stop-color="#22c55e" stop-opacity="0" />
                    </linearGradient>
                  </defs>

                  <!-- gridline ngang rất nhẹ -->
                  <g stroke="rgba(148,163,184,0.25)" stroke-width="0.3">
                    <line x1="12" y1="9"  x2="96" y2="9"  />
                    <line x1="12" y1="17" x2="96" y2="17" />
                    <line x1="12" y1="25" x2="96" y2="25" />
                  </g>

                  <!-- trục Y mảnh -->
                  <line x1="12" y1="6" x2="12" y2="30"
                        stroke="rgba(148,163,184,0.6)" stroke-width="0.6" />
                  <!-- trục X mảnh -->
                  <line x1="12" y1="30" x2="96" y2="30"
                        stroke="rgba(148,163,184,0.6)" stroke-width="0.6" />

                  <!-- tick Y + label nhỏ -->
                  <line x1="11" y1="25" x2="12" y2="25"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.5" />
                  <line x1="11" y1="17" x2="12" y2="17"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.5" />
                  <line x1="11" y1="9"  x2="12" y2="9"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.5" />
                  <text x="3" y="27.5" font-size="3.5" fill="rgba(148,163,184,0.8)">2.5k</text>
                  <text x="3" y="19.7" font-size="3.5" fill="rgba(148,163,184,0.8)">3.5k</text>
                  <text x="3" y="11.8" font-size="3.5" fill="rgba(148,163,184,0.8)">4.5k</text>

                  <!-- area dưới đường -->
                  <path d="M12,26 L22,26 L34,25 L46,23 L58,21 L70,18 L82,16 L94,14 L94,30 L12,30 Z"
                        fill="url(#trendFill)" />

                  <!-- đường trend mảnh, không glow -->
                  <polyline points="12,26 22,26 34,25 46,23 58,21 70,18 82,16 94,14"
                            stroke="#22c55e" stroke-width="0.9" fill="none"
                            stroke-linejoin="round" stroke-linecap="round" />

                  <!-- chấm nhỏ trên đường -->
                  <g fill="#22c55e">
                    <circle cx="12" cy="26" r="0.8" />
                    <circle cx="34" cy="25" r="0.8" />
                    <circle cx="58" cy="21" r="0.8" />
                    <circle cx="82" cy="16" r="0.8" />
                    <circle cx="94" cy="14" r="0.9" />
                  </g>
                </svg>
                <div class="trend-x-axis">
                  <span>RUN_01</span>
                  <span>RUN_04</span>
                  <span>RUN_07</span>
                  <span>RUN_10</span>
                </div>
              </div>
            </div>
          </div>
          <!-- RIGHT -->'''

new_html, n = re.subn(pattern, replacement, html)
print(f"[INFO] trend block replaced: {n}")
if n:
    p.write_text(new_html, encoding="utf-8")
