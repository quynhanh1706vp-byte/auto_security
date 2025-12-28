#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p460_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need find; need grep; need sed
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/log.txt"; }

log "[INFO] OUT=$OUT SVC=$SVC BASE=$BASE"

python3 - <<'PY'
from pathlib import Path
import datetime, re

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
tpl = root / "templates"
out = root / "out_ci"
ts  = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

marker = "VSP_SIDEBAR_V1"
js_marker = "VSP_SIDEBAR_JS_V1"

css = r"""
<!-- VSP_SIDEBAR_V1: injected sidebar layout -->
<style>
  :root{
    --vsp-bg: #0b1020;
    --vsp-panel: #0f1730;
    --vsp-panel2: #0c142b;
    --vsp-line: rgba(255,255,255,.08);
    --vsp-text: rgba(255,255,255,.86);
    --vsp-muted: rgba(255,255,255,.58);
    --vsp-accent: #7aa2ff;
  }
  body{ margin:0; background:var(--vsp-bg); color:var(--vsp-text); }
  .vsp_shell{ min-height:100vh; display:flex; }
  .vsp_sidebar{
    width: 252px;
    background: linear-gradient(180deg,var(--vsp-panel),var(--vsp-panel2));
    border-right:1px solid var(--vsp-line);
    padding: 14px 12px;
    position: sticky; top:0; height:100vh; overflow:auto;
  }
  .vsp_brand{ font-weight:700; letter-spacing:.4px; font-size:14px; margin:2px 8px 10px; }
  .vsp_brand small{ display:block; font-weight:500; color:var(--vsp-muted); margin-top:3px; }
  .vsp_nav{ display:flex; flex-direction:column; gap:6px; margin-top:10px; }
  .vsp_nav a{
    display:flex; align-items:center; gap:10px;
    padding:10px 10px; border-radius:12px;
    text-decoration:none; color:var(--vsp-text);
    border:1px solid transparent;
  }
  .vsp_nav a:hover{ border-color: var(--vsp-line); background: rgba(255,255,255,.04); }
  .vsp_nav a.active{
    border-color: rgba(122,162,255,.35);
    background: rgba(122,162,255,.12);
    box-shadow: 0 0 0 1px rgba(122,162,255,.10) inset;
  }
  .vsp_nav .ico{
    width:28px; height:28px; border-radius:10px;
    background: rgba(255,255,255,.06);
    display:flex; align-items:center; justify-content:center;
    border:1px solid var(--vsp-line);
    font-size:12px; color:var(--vsp-muted);
  }
  .vsp_div{ height:1px; background: var(--vsp-line); margin:12px 6px; }
  .vsp_hint{ margin:10px 8px 0; color:var(--vsp-muted); font-size:12px; line-height:1.35; }
  .vsp_main{ flex:1; min-width:0; padding: 14px 16px; }
  /* hide common top navs if exist (safe no-op if not found) */
  .vsp-topnav, .topnav, .navbar, #topnav, #navbar, #vsp_top_nav{ display:none !important; }
</style>
"""

sidebar = r"""
<!-- VSP_SIDEBAR_V1 -->
<div class="vsp_shell">
  <aside class="vsp_sidebar">
    <div class="vsp_brand">VSP / SECURITY_BUNDLE
      <small>Commercial UI (5 tabs)</small>
    </div>

    <nav class="vsp_nav">
      <a href="/c/dashboard" data-path="/c/dashboard"><span class="ico">KP</span><span>Dashboard</span></a>
      <a href="/c/runs" data-path="/c/runs"><span class="ico">RN</span><span>Runs & Reports</span></a>
      <a href="/c/data_source" data-path="/c/data_source"><span class="ico">DS</span><span>Data Source</span></a>
      <a href="/c/settings" data-path="/c/settings"><span class="ico">ST</span><span>Settings</span></a>
      <a href="/c/rule_overrides" data-path="/c/rule_overrides"><span class="ico">RO</span><span>Rule Overrides</span></a>

      <div class="vsp_div"></div>

      <a href="/vsp5" data-path="/vsp5"><span class="ico">LG</span><span>Legacy /vsp5</span></a>
    </nav>

    <div class="vsp_hint">
      Tip: Sidebar auto-highlight theo URL.<br/>
      Mục tiêu: UI ổn định + log sạch + export/pack đầy đủ.
    </div>
  </aside>

  <main class="vsp_main">
"""

sidebar_close = r"""
  </main>
</div>
"""

js = r"""
<!-- VSP_SIDEBAR_JS_V1 -->
<script>
(function(){
  try{
    var p = (location && location.pathname) ? location.pathname : "";
    var links = document.querySelectorAll('.vsp_nav a[data-path]');
    links.forEach(function(a){
      var dp = a.getAttribute('data-path') || '';
      if(!dp) return;
      if(p === dp || (dp !== '/' && p.startsWith(dp))) a.classList.add('active');
    });
  }catch(e){}
})();
</script>
"""

def patch_file(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        return False, "skip(marker)"

    if "</head>" not in s or "<body" not in s or "</body>" not in s:
        return False, "skip(no head/body)"

    # backup
    bak = fp.with_suffix(fp.suffix + f".bak_p460_{ts}")
    bak.write_text(s, encoding="utf-8")

    # inject css before </head>
    s2 = s.replace("</head>", css + "\n</head>", 1)

    # inject sidebar right after <body...>
    m = re.search(r"<body\b[^>]*>", s2, flags=re.I)
    if not m:
        return False, "skip(no body tag match)"
    insert_at = m.end()
    s2 = s2[:insert_at] + "\n" + sidebar + "\n" + s2[insert_at:]

    # inject js + close wrapper before </body>
    if js_marker not in s2:
        s2 = s2.replace("</body>", "\n" + js + "\n" + sidebar_close + "\n</body>", 1)
    else:
        s2 = s2.replace("</body>", "\n" + sidebar_close + "\n</body>", 1)

    fp.write_text(s2, encoding="utf-8")
    return True, str(bak)

tpl_dir = tpl
if not tpl_dir.exists():
    print("[ERR] templates/ not found")
    raise SystemExit(2)

targets = []
for fp in tpl_dir.rglob("*.html"):
    txt = fp.read_text(encoding="utf-8", errors="replace")
    # ưu tiên template nào có link /c/ hoặc nhắc dashboard/runs/settings
    if ("/c/" in txt) or ("Dashboard" in txt and "Runs" in txt) or ("rule_overrides" in txt):
        targets.append(fp)

if not targets:
    # fallback: patch all html under templates
    targets = list(tpl_dir.rglob("*.html"))

patched = []
skipped = []
for fp in sorted(set(targets)):
    ok, info = patch_file(fp)
    if ok: patched.append((str(fp), info))
    else: skipped.append((str(fp), info))

print("[INFO] patched =", len(patched))
for a,b in patched[:120]:
    print(" -", a, "bak:", b)
print("[INFO] skipped =", len(skipped))
PY | tee "$OUT/patch_report.txt"

log "[INFO] restart service"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
else
  systemctl restart "$SVC" || true
fi

log "[INFO] quick reach check"
if command -v curl >/dev/null 2>&1; then
  curl -fsS --connect-timeout 1 --max-time 3 "$BASE/c/dashboard" -o "$OUT/c_dashboard.html" && log "[OK] /c/dashboard reachable" || log "[WARN] /c/dashboard not reachable yet"
fi

log "[DONE] open $OUT/patch_report.txt and refresh browser (Ctrl+Shift+R)"
