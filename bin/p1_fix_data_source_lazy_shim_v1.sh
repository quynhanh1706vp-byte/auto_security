#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p static/js

python3 - <<'PY'
from pathlib import Path
import re, time, textwrap

# try to discover actual lazy filename from templates / js
cand = []
roots = [Path("templates"), Path("static/js")]
for root in roots:
    if not root.exists(): 
        continue
    for p in root.rglob("*"):
        if p.is_file() and p.suffix in (".html",".js"):
            t = p.read_text(encoding="utf-8", errors="replace")
            for m in re.findall(r'(/static/js/(vsp_data_source_lazy[^"\']+\.js))', t):
                cand.append(m[1])

lazy_name = None
if cand:
    # pick most common
    lazy_name = sorted(set(cand), key=lambda x: (-cand.count(x), x))[0]
else:
    lazy_name = "vsp_data_source_lazy_v1.js"

lazy_path = Path("static/js") / lazy_name
bak = f"{lazy_path}.bak_{int(time.time())}"
if lazy_path.exists():
    lazy_path.replace(bak)
    print("[BACKUP]", bak)

# pick real DS script candidates
cands = [
    "vsp_data_source_tab_v3.js",
    "vsp_data_source_tab_v2.js",
    "vsp_data_source_lazy_v1.js",  # (avoid loop but ok)
    "vsp_data_source_charts_v1.js",
]
existing = [x for x in cands if (Path("static/js")/x).exists() and x != lazy_name]

target_list = existing[:2] if existing else ["vsp_data_source_tab_v3.js"]

lazy_path.write_text(textwrap.dedent(f"""
/* VSP_P1_DATA_SOURCE_LAZY_SHIM_V1
   - This file exists to prevent MIME-type JSON execution block.
   - It loads the real Data Source JS modules if present.
*/
(()=>{{
  try {{
    const ver = String(Date.now());
    const targets = {target_list!r};
    const load = (src)=> new Promise((res)=>{{
      const s=document.createElement('script');
      s.src='/static/js/'+src + (src.includes('?') ? '' : ('?v='+ver));
      s.async=true;
      s.onload=()=>res(true);
      s.onerror=()=>res(false);
      document.head.appendChild(s);
    }});
    (async()=>{{
      for(const t of targets) {{
        try {{ await load(t); }} catch(e){{}}
      }}
      try {{ console.log("[DataSourceLazyShimV1] loaded:", targets.join(", ")); }} catch(e){{}}
    }})();
  }} catch(e){{}}
}})();
""").strip()+"\n", encoding="utf-8")

print("[OK] wrote shim:", lazy_path)
PY
