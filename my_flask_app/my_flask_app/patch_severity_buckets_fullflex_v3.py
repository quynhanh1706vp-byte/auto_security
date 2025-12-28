import pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
data = path.read_text(encoding="utf-8")

marker = "SEVERITY BUCKETS"
idx = data.find(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy 'SEVERITY BUCKETS' trong file.")

# Tìm <table> gần ngay sau chữ "SEVERITY BUCKETS"
after = data[idx:]
table_start_rel = after.find("<table")
table_end_rel = after.find("</table>", table_start_rel)
if table_start_rel == -1 or table_end_rel == -1:
    raise SystemExit("[ERR] Không tìm thấy block <table> sau 'SEVERITY BUCKETS'.")

t_start = idx + table_start_rel
t_end = idx + table_end_rel + len("</table>")

new_block = """
        <!-- Header Severity / Count -->
        <div class="flex justify-between text-xs text-slate-300 mt-4 mb-1">
          <span>Severity</span>
          <span>Count</span>
        </div>

        <!-- Full-width bars (flex layout) -->
        <div class="space-y-3 text-sm">
          <!-- Critical -->
          <div class="flex items-center gap-3">
            <span class="w-20">Critical</span>
            <div class="flex-1 h-1.5 bg-slate-900/80 rounded-full overflow-hidden">
              <!-- 5% cho có vạch nhỏ, dù count=0 -->
              <div class="h-full bg-slate-700" style="width:5%;"></div>
            </div>
            <span class="w-10 text-right text-xs font-semibold text-red-500"
                  id="sev-table-critical">0</span>
          </div>

          <!-- High -->
          <div class="flex items-center gap-3">
            <span class="w-20">High</span>
            <div class="flex-1 h-1.5 bg-slate-900/80 rounded-full overflow-hidden">
              <div class="h-full bg-orange-400" style="width:40%;"></div>
            </div>
            <span class="w-10 text-right text-xs font-semibold text-orange-400"
                  id="sev-table-high">170</span>
          </div>

          <!-- Medium -->
          <div class="flex items-center gap-3">
            <span class="w-20">Medium</span>
            <div class="flex-1 h-1.5 bg-slate-900/80 rounded-full overflow-hidden">
              <div class="h-full bg-yellow-400" style="width:100%;"></div>
            </div>
            <span class="w-10 text-right text-xs font-semibold text-yellow-400"
                  id="sev-table-medium">8891</span>
          </div>

          <!-- Low -->
          <div class="flex items-center gap-3">
            <span class="w-20">Low</span>
            <div class="flex-1 h-1.5 bg-slate-900/80 rounded-full overflow-hidden">
              <div class="h-full bg-cyan-400" style="width:20%;"></div>
            </div>
            <span class="w-10 text-right text-xs font-semibold text-cyan-400"
                  id="sev-table-low">10</span>
          </div>
        </div>
"""

data = data[:t_start] + new_block + data[t_end:]
path.write_text(data, encoding="utf-8")
print("[OK] Đã thay block SEVERITY BUCKETS bằng layout flex full-width bars.")
