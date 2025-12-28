#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8910}"

python3 - <<'PY'
import re, sys
from urllib.request import Request, urlopen

BASE = "http://127.0.0.1:8910"
url = BASE + "/vsp5"
req = Request(url, headers={"User-Agent":"vsp-probe/1.0"})
with urlopen(req, timeout=3) as r:
    code = getattr(r, "status", None)
    data = r.read(250_000)  # đọc tối đa 250KB để khỏi out
html = data.decode("utf-8", "ignore")

def find_tag(pat):
    m = re.search(pat, html, re.I)
    return m.group(0) if m else None

print("status=", code)
print("len(read)=", len(data))

need = [
  ("CIO_CSS", r'vsp_cio_shell_v1\.css[^"\']*'),
  ("CIO_JS",  r'vsp_cio_shell_apply_v1\.js[^"\']*'),
  ("LUXE",    r'vsp_dashboard_luxe_v1\.js[^"\']*'),
]
for name, kw in need:
    print(f"{name}=", ("YES" if re.search(kw, html, re.I) else "NO"))

print("\n-- script/link tags found (first 1 each) --")
print("CIO_CSS_TAG:", find_tag(r'<link[^>]+vsp_cio_shell_v1\.css[^>]*>') or "NONE")
print("CIO_JS_TAG:",  find_tag(r'<script[^>]+vsp_cio_shell_apply_v1\.js[^>]*></script>') or "NONE")
print("LUXE_TAG:",    find_tag(r'<script[^>]+vsp_dashboard_luxe_v1\.js[^>]*></script>') or "NONE")
PY
