#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
text = p.read_text(encoding="utf-8")

# --- 1) Sửa CSS TREND + BAR (giảm sáng, thêm trục) ---
css_pattern = r"""/\* TREND[\s\S]+?/\* BAR CHART \*/"""
css_replacement = r"""/* TREND – nhỏ lại, tắt glow */
    .trend-area {
      position: relative;
      flex: 1;
      min-height: 110px;
      height: 110px;
      border-radius: 14px;
      background: #020617;
      padding: 8px 12px 18px;
      overflow: hidden;
      border: 1px solid rgba(30, 64, 175, 0.5);
    }

    .trend-svg {
      width: 100%;
      height: 100%;
      display: block;
      /* bỏ drop-shadow để không sáng */
      filter: none;
    }

    .trend-x-axis {
      position: absolute;
      left: 32px;
      right: 18px;
      bottom: 4px;
      display: flex;
      justify-content: space-between;
      font-size: 9px;
      color: rgba(148, 163, 184, 0.7);
    }

    .trend-x-axis span { white-space: nowrap; }

    /* BAR CHART – tắt glow, màu trầm hơn */
    .bar-wrapper {
      flex: 1;
      min-height: 140px;
      display: flex;
      align-items: flex-end;
      gap: 10px;
      padding: 6px 4px 4px;
    }

    .bar {
      flex: 1;
      border-radius: 8px 8px 0 0;
      background: linear-gradient(180deg, #facc15, #b45309);
      box-shadow: none;
      height: 120px;
    }

    .bar-muted {
      flex: 1;
      height: 28px;
      border-radius: 8px 8px 0 0;
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
text, n1 = re.subn(css_pattern, css_replacement, text)
print(f"[INFO] CSS blocks patched: {n1}")

# --- 2) Sửa SVG Trend: thêm trục X/Y, line nhỏ, màu dịu ---
svg_pattern = r"""<div class="trend-area">[\s\S]+?</div>\s*</div>"""
svg_replacement = r"""<div class="trend-area">
                <svg class="trend-svg" viewBox="0 0 100 40" preserveAspectRatio="none">
                  <defs>
                    <linearGradient id="trendFill" x1="0" x2="0" y1="0" y2="1">
                      <stop offset="0%" stop-color="#4ade80" stop-opacity="0.22" />
                      <stop offset="100%" stop-color="#4ade80" stop-opacity="0" />
                    </linearGradient>
                  </defs>
                  <!-- trục tung (Y) -->
                  <line x1="10" y1="5" x2="10" y2="35"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.5" />
                  <!-- trục hoành (X) -->
                  <line x1="10" y1="35" x2="98" y2="35"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.5" />
                  <!-- area dưới đường -->
                  <path d="M10,30 L20,30 L32,29 L44,27 L56,25 L68,22 L80,20 L92,18 L92,35 L10,35 Z"
                        fill="url(#trendFill)" />
                  <!-- đường trend (line nhỏ, không sáng) -->
                  <polyline points="10,30 20,30 32,29 44,27 56,25 68,22 80,20 92,18"
                            stroke="#4ade80" stroke-width="1.1" fill="none"
                            stroke-linejoin="round" stroke-linecap="round" />
                  <!-- điểm nhỏ trên đường -->
                  <circle cx="10" cy="30" r="0.9" fill="#4ade80"/>
                  <circle cx="32" cy="29" r="0.9" fill="#4ade80"/>
                  <circle cx="56" cy="25" r="0.9" fill="#4ade80"/>
                  <circle cx="80" cy="20" r="0.9" fill="#4ade80"/>
                  <circle cx="92" cy="18" r="1.0" fill="#4ade80"/>
                  <!-- tick + label trục Y -->
                  <text x="6" y="34" font-size="7" fill="rgba(148,163,184,0.7)">2.5k</text>
                  <text x="6" y="26" font-size="7" fill="rgba(148,163,184,0.7)">3.5k</text>
                  <text x="6" y="18" font-size="7" fill="rgba(148,163,184,0.7)">4.5k</text>
                  <line x1="9" y1="26" x2="10" y2="26"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.5" />
                  <line x1="9" y1="18" x2="10" y2="18"
                        stroke="rgba(148,163,184,0.7)" stroke-width="0.5" />
                </svg>
                <div class="trend-x-axis">
                  <span>RUN_01</span>
                  <span>RUN_04</span>
                  <span>RUN_07</span>
                  <span>RUN_10</span>
                </div>
              </div>
            </div>"""
text, n2 = re.subn(svg_pattern, svg_replacement, text)
print(f"[INFO] SVG trend patched: {n2}")

if n1 == 0 or n2 == 0:
    print("[WARN] Một trong các block không tìm thấy, kiểm tra lại file HTML!")
p.write_text(text, encoding="utf-8")
