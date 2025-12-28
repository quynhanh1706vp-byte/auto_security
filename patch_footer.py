from pathlib import Path

p = Path("app.py")
text = p.read_text(encoding="utf-8")

old = '''  <div class="footer">
    <div>Data source: <code>{{ run_dir }}/report/summary_unified.json</code> &amp; <code>findings.json</code></div>
    <div>UI state file: <code>{{ state_file }}</code></div>
    <div>Tool config file: <code>{{ tool_config_file }}</code></div>
  </div>
</div>
</body>
</html>
"""
'''

new = '''  <div class="footer">
    <div>
      <div><strong>Data source</strong></div>
      <code>{{ run_dir }}/report/</code><br>
      ├─ <code>summary_unified.json</code><br>
      └─ <code>findings.json</code>
    </div>
    <div>
      <div><strong>UI state</strong></div>
      <code>{{ state_file }}</code>
    </div>
    <div>
      <div><strong>Tool config</strong></div>
      <code>{{ tool_config_file }}</code>
    </div>
  </div>
</div>
</body>
</html>
"""
'''

if old not in text:
    print("[ERR] Footer block not found, không patch được.")
else:
    p.write_text(text.replace(old, new), encoding="utf-8")
    print("[OK] Updated footer for Data source.")
