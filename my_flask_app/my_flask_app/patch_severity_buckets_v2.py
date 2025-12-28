import pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
data = path.read_text(encoding="utf-8")

marker = "Severity buckets"
idx = data.find(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy 'Severity buckets' trong file.")

after = data[idx:]
tbody_start_rel = after.find("<tbody")
if tbody_start_rel == -1:
    raise SystemExit("[ERR] Không tìm thấy <tbody sau marker.")

tbody_end_rel = after.find("</tbody>", tbody_start_rel)
if tbody_end_rel == -1:
    raise SystemExit("[ERR] Không tìm thấy </tbody sau marker.")

tbody_start = idx + tbody_start_rel
tbody_end = idx + tbody_end_rel + len("</tbody>")

new_tbody = """
        <tbody class="divide-y divide-slate-900/70">
          <tr>
            <td class="py-2">Critical</td>
            <td class="py-2">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-red-500" id="sev-table-critical">0</span>
                <div class="flex-1 max-w-[140px] h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:3%; background:#ef4444;"></div>
                </div>
              </div>
            </td>
          </tr>
          <tr>
            <td class="py-2">High</td>
            <td class="py-2">
              <div class="flex items-center justify-end gap-3">
                <span class="text-xs font-semibold text-orange-400" id="sev-table-high">170</span>
                <div class="flex-1 max-w-[140px] h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
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
                <div class="flex-1 max-w-[140px] h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
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
                <div class="flex-1 max-w-[140px] h-1.5 bg-slate-900/90 rounded-full overflow-hidden">
                  <div class="h-full" style="width:15%; background:#22d3ee;"></div>
                </div>
              </div>
            </td>
          </tr>
        </tbody>
"""

data = data[:tbody_start] + new_tbody + data[tbody_end:]
path.write_text(data, encoding="utf-8")
print("[OK] Đã cập nhật block 'Severity buckets'.")
