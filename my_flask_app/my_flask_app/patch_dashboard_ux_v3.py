import pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
data = path.read_text(encoding="utf-8")

# =========================
# 1) Phóng to thanh Severity buckets
# =========================
marker = "Severity buckets"
idx = data.find(marker)
if idx != -1:
    after = data[idx:]
    tb_start_rel = after.find("<tbody")
    tb_end_rel = after.find("</tbody>", tb_start_rel)
    if tb_start_rel != -1 and tb_end_rel != -1:
        tb_start = idx + tb_start_rel
        tb_end = idx + tb_end_rel + len("</tbody>")

        new_tbody = '''
        <tbody class="divide-y divide-slate-900/70">
          <tr>
            <td class="py-2">Critical</td>
            <td class="py-2">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-red-500" id="sev-table-critical">0</span>
                <div class="flex-1 max-w-[160px] h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:4%; background:#ef4444;"></div>
                </div>
              </div>
            </td>
          </tr>
          <tr>
            <td class="py-2">High</td>
            <td class="py-2">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-orange-400" id="sev-table-high">170</span>
                <div class="flex-1 max-w-[160px] h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:35%; background:#f97316;"></div>
                </div>
              </div>
            </td>
          </tr>
          <tr>
            <td class="py-2">Medium</td>
            <td class="py-2">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-yellow-400" id="sev-table-medium">8891</span>
                <div class="flex-1 max-w-[160px] h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:100%; background:#facc15;"></div>
                </div>
              </div>
            </td>
          </tr>
          <tr>
            <td class="py-2">Low</td>
            <td class="py-2">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-cyan-400" id="sev-table-low">10</span>
                <div class="flex-1 max-w-[160px] h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:15%; background:#22d3ee;"></div>
                </div>
              </div>
            </td>
          </tr>
        </tbody>
        '''
        data = data[:tb_start] + new_tbody + data[tb_end:]
    else:
        print("[WARN] Không tìm thấy <tbody> cho 'Severity buckets'.")

# =========================
# 2) Thêm CSS hover cho Run overview + Top risk
# =========================
if "run-overview-table tbody tr:hover" not in data:
    extra_css = """
    .run-overview-table tbody tr:hover,
    .top-risk-table tbody tr:hover {
      background: rgba(15, 23, 42, 0.85);
    }
"""
    style_marker = "</style>"
    sidx = data.find(style_marker)
    if sidx != -1:
        data = data[:sidx] + extra_css + "\n" + data[sidx:]
    else:
        print("[WARN] Không tìm thấy </style> để chèn CSS hover.")

# =========================
# 3) Gán class cho bảng Run overview + Top risk
# =========================
for label, cls in [("<!-- RUN OVERVIEW", "run-overview-table"),
                   ("<!-- TOP RISK FINDINGS", "top-risk-table")]:
    idx = data.find(label)
    if idx == -1:
        continue
    after = data[idx:]
    t_start_rel = after.find("<table")
    if t_start_rel == -1:
        continue
    t_start = idx + t_start_rel
    tag_end = data.find(">", t_start)
    if tag_end == -1:
        continue

    table_tag = data[t_start:tag_end]
    if cls in table_tag:
        continue  # đã patch

    if 'class="' in table_tag:
        new_table_tag = table_tag.replace('class="', f'class="{cls} ')
    else:
        new_table_tag = table_tag.replace("<table", f'<table class="{cls}"')

    data = data[:t_start] + new_table_tag + data[tag_end:]

path.write_text(data, encoding="utf-8")
print("[OK] Đã patch Severity buckets + hover bảng.")
