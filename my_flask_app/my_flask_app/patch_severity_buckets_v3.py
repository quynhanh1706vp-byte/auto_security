import pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
data = path.read_text(encoding="utf-8")

marker = "SEVERITY BUCKETS"
idx = data.find(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy 'SEVERITY BUCKETS' trong file.")

after = data[idx:]
tb_start_rel = after.find("<tbody")
tb_end_rel = after.find("</tbody>", tb_start_rel)
if tb_start_rel == -1 or tb_end_rel == -1:
    raise SystemExit("[ERR] Không tìm thấy <tbody...</tbody> sau marker.")

tb_start = idx + tb_start_rel
tb_end = idx + tb_end_rel + len("</tbody>")

new_tbody = """
        <tbody class="divide-y divide-slate-900/70">
          <tr>
            <td class="py-2 pt-3">Critical</td>
            <td class="py-2 pt-3">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-red-500" id="sev-table-critical">0</span>
                <div class="w-40 h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:8%; background:#ef4444;"></div>
                </div>
              </div>
            </td>
          </tr>
          <tr>
            <td class="py-2">High</td>
            <td class="py-2">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-orange-400" id="sev-table-high">170</span>
                <div class="w-40 h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:60%; background:#f97316;"></div>
                </div>
              </div>
            </td>
          </tr>
          <tr>
            <td class="py-2">Medium</td>
            <td class="py-2">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-yellow-400" id="sev-table-medium">8891</span>
                <div class="w-40 h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:100%; background:#facc15;"></div>
                </div>
              </div>
            </td>
          </tr>
          <tr>
            <td class="py-2 pb-3">Low</td>
            <td class="py-2 pb-3">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-cyan-400" id="sev-table-low">10</span>
                <div class="w-40 h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:30%; background:#22d3ee;"></div>
                </div>
              </div>
            </td>
          </tr>
        </tbody>
"""

data = data[:tb_start] + new_tbody + data[tb_end:]
path.write_text(data, encoding="utf-8")
print("[OK] Đã phóng to thanh 'Severity buckets' + cân lại khoảng cách.")
