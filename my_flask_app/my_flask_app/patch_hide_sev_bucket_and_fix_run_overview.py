import pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
data = path.read_text(encoding="utf-8")

# =========================
# 1) Ẩn card "SEVERITY BUCKETS"
# =========================
marker_sb = "SEVERITY BUCKETS"
idx_sb = data.find(marker_sb)
if idx_sb != -1:
    # Tìm <div class="card ..."> gần nhất phía trước marker
    before = data[:idx_sb]
    div_idx = before.rfind('<div class="card')
    if div_idx != -1:
        tag_end = data.find(">", div_idx)
        if tag_end != -1:
            tag = data[div_idx:tag_end]
            if "hidden" not in tag:
                if 'class="' in tag:
                    new_tag = tag.replace('class="', 'class="hidden ')
                else:
                    new_tag = tag.replace("<div", '<div class="hidden"')
                data = data[:div_idx] + new_tag + data[tag_end:]
                print("[OK] Đã thêm 'hidden' cho card SEVERITY BUCKETS.")
else:
    print("[WARN] Không tìm thấy 'SEVERITY BUCKETS'.")

# =========================
# 2) Thay bảng By tool trong RUN OVERVIEW
# =========================
marker_ro = "By tool"
idx_ro = data.find(marker_ro)
if idx_ro == -1:
    print("[WARN] Không tìm thấy 'By tool' để patch Run overview.")
else:
    after = data[idx_ro:]
    table_start_rel = after.find("<table")
    table_end_rel = after.find("</table>", table_start_rel)
    if table_start_rel == -1 or table_end_rel == -1:
        print("[WARN] Không tìm thấy block <table> By tool.")
    else:
        t_start = idx_ro + table_start_rel
        t_end = idx_ro + table_end_rel + len("</table>")

        new_table = """
        <table class="w-full text-xs md:text-sm run-overview-table">
          <thead class="border-b border-slate-800 text-slate-400">
            <tr>
              <th class="py-2 text-left">Tool</th>
              <th class="py-2 text-right">C</th>
              <th class="py-2 text-right">H</th>
              <th class="py-2 text-right">M</th>
              <th class="py-2 text-right">L</th>
              <th class="py-2 text-right">Total</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-900/70">
            <tr>
              <td class="py-2">gitleaks</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right text-orange-400">26</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right text-lime-400 font-semibold">26</td>
            </tr>
            <tr>
              <td class="py-2">grype</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right text-orange-400">1</td>
              <td class="py-2 text-right text-yellow-400">1</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right text-lime-400 font-semibold">2</td>
            </tr>
            <tr>
              <td class="py-2">bandit</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right text-orange-400">45</td>
              <td class="py-2 text-right text-yellow-400">23</td>
              <td class="py-2 text-right text-cyan-400">5</td>
              <td class="py-2 text-right text-lime-400 font-semibold">73</td>
            </tr>
            <tr>
              <td class="py-2">trivy_fs</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right text-orange-400">8</td>
              <td class="py-2 text-right text-yellow-400">32</td>
              <td class="py-2 text-right text-cyan-400">5</td>
              <td class="py-2 text-right text-lime-400 font-semibold">45</td>
            </tr>
            <tr>
              <td class="py-2">semgrep</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right text-orange-400">90</td>
              <td class="py-2 text-right text-yellow-400">8835</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right text-lime-400 font-semibold">8925</td>
            </tr>
            <tr class="border-t border-slate-800 text-slate-300">
              <td class="py-2 font-semibold">Total</td>
              <td class="py-2 text-right">0</td>
              <td class="py-2 text-right">170</td>
              <td class="py-2 text-right">8891</td>
              <td class="py-2 text-right">10</td>
              <td class="py-2 text-right font-bold text-lime-400">9071</td>
            </tr>
          </tbody>
        </table>
        """

        data = data[:t_start] + new_table + data[t_end:]
        print("[OK] Đã thay bảng Run overview (By tool) với số liệu chuẩn.")

path.write_text(data, encoding="utf-8")
