import pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
data = path.read_text(encoding="utf-8")

marker = "SEVERITY BUCKETS"
idx = data.find(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy 'SEVERITY BUCKETS' trong file.")

after = data[idx:]
table_start_rel = after.find("<table")
table_end_rel = after.find("</table>", table_start_rel)
if table_start_rel == -1 or table_end_rel == -1:
    raise SystemExit("[ERR] Không tìm thấy block <table> sau 'SEVERITY BUCKETS'.")

t_start = idx + table_start_rel
t_end = idx + table_end_rel + len("</table>")

new_block = """
        <!-- Header Severity / Count -->
        <div class="flex justify-between text-sm text-slate-300 mt-4">
          <div>Severity</div>
          <div>Count</div>
        </div>

        <!-- Full-width bars -->
        <div class="mt-3 space-y-3 text-sm">
          <div class="flex items-center gap-4">
            <div class="w-24">Critical</div>
            <div class="flex-1">
              <div class="h-1.5 bg-slate-900/80 rounded-full overflow-hidden">
                <div class="h-full" style="width:2%; background:#ef4444;"></div>
              </div>
            </div>
            <div class="w-12 text-right text-xs font-semibold text-red-500" id="sev-table-critical">0</div>
          </div>

          <div class="flex items-center gap-4">
            <div class="w-24">High</div>
            <div class="flex-1">
              <div class="h-1.5 bg-slate-900/80 rounded-full overflow-hidden">
                <div class="h-full" style="width:30%; background:#f97316;"></div>
              </div>
            </div>
            <div class="w-12 text-right text-xs font-semibold text-orange-400" id="sev-table-high">170</div>
          </div>

          <div class="flex items-center gap-4">
            <div class="w-24">Medium</div>
            <div class="flex-1">
              <div class="h-1.5 bg-slate-900/80 rounded-full overflow-hidden">
                <div class="h-full" style="width:100%; background:#facc15;"></div>
              </div>
            </div>
            <div class="w-12 text-right text-xs font-semibold text-yellow-400" id="sev-table-medium">8891</div>
          </div>

          <div class="flex items-center gap-4">
            <div class="w-24">Low</div>
            <div class="flex-1">
              <div class="h-1.5 bg-slate-900/80 rounded-full overflow-hidden">
                <div class="h-full" style="width:20%; background:#22d3ee;"></div>
              </div>
            </div>
            <div class="w-12 text-right text-xs font-semibold text-cyan-400" id="sev-table-low">10</div>
          </div>
        </div>
"""

data = data[:t_start] + new_block + data[t_end:]
path.write_text(data, encoding="utf-8")
print("[OK] Đã thay block SEVERITY BUCKETS bằng layout full-width bars.")
