#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v node >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
CSS="static/css/vsp_dashboard_polish_v1.css"

mkdir -p "$(dirname "$CSS")"
if [ ! -s "$CSS" ]; then
  cat > "$CSS" <<'CSS'
/* VSP_DASHBOARD_POLISH_V1 (force-visible) */
:root{
  --vsp-accent: rgba(56,189,248,.85);
  --vsp-accent2: rgba(168,85,247,.70);
}
body{
  background:
    radial-gradient(900px 520px at 20% 18%, rgba(56,189,248,.08), transparent 60%),
    radial-gradient(900px 520px at 82% 12%, rgba(168,85,247,.06), transparent 60%),
    #070e1a !important;
}
.vsp5nav{
  backdrop-filter: blur(10px);
  background: rgba(0,0,0,.30) !important;
  border-bottom: 1px solid rgba(255,255,255,.10) !important;
}
.vsp5nav a{
  border-color: rgba(56,189,248,.22) !important;
  box-shadow: 0 0 0 1px rgba(168,85,247,.10) inset;
}
.vsp5nav a:hover{ background: rgba(56,189,248,.08) !important; }
CSS
  echo "[OK] wrote $CSS"
else
  echo "[OK] css exists: $CSS"
fi

python3 - <<PY
from pathlib import Path
import re, shutil

TS="${TS}"
MARK="VSP_P1_FIX_VSP5_DUP_GATE_STORY_AND_POLISH_CSS_V2"
CSS_LINK=f'<link rel="stylesheet" href="/static/css/vsp_dashboard_polish_v1.css?v={TS}"/>'

# Candidates: templates + key python files
cands = []
cands += list(Path("templates").glob("*.html"))
for f in ["vsp_demo_app.py","wsgi_vsp_ui_gateway.py"]:
    p = Path(f)
    if p.exists(): cands.append(p)

# Helper: backup
def backup(p: Path):
    bak = p.with_name(p.name + f".bak_fixvsp5_{TS}")
    shutil.copy2(p, bak)
    print(f"[BACKUP] {bak}")

# Identify likely /vsp5 renderer: contains BOTH bundle + luxe (as seen in your /vsp5 HTML)
def is_vsp5_renderer(s: str) -> bool:
    return ("vsp_bundle_commercial_v2.js" in s) and ("vsp_dashboard_luxe_v1.js" in s) and ("/vsp5" in s)

# Dedupe gate_story script tags in HTML-ish content
gate_pat = re.compile(r'<script[^>]+src=["\']/static/js/vsp_dashboard_gate_story_v1\.js[^"\']*["\'][^>]*>\s*</script>\s*', re.I)

def patch_text(s: str):
    changed = False

    # 1) ensure CSS link exists (inject before </head> if possible)
    if "vsp_dashboard_polish_v1.css" not in s:
        if "</head>" in s.lower():
            s2 = re.sub(r'</head\s*>', CSS_LINK + "\n</head>", s, count=1, flags=re.I)
            if s2 != s:
                s = s2; changed = True
        elif "<head" in s.lower():
            # insert after first <head...>
            s2 = re.sub(r'(<head[^>]*>)', r'\1\n  ' + CSS_LINK + "\n", s, count=1, flags=re.I)
            if s2 != s:
                s = s2; changed = True

    # 2) dedupe gate_story script tags (keep first)
    ms = list(gate_pat.finditer(s))
    if len(ms) > 1:
        first = ms[0].group(0)
        # remove all gate_story then re-insert one at first position
        s_wo = gate_pat.sub("", s)
        # put first back where the first match started (best effort)
        s = s_wo[:ms[0].start()] + first + s_wo[ms[0].start():]
        changed = True
        print(f"[OK] dedupe gate_story: {len(ms)} -> 1")
    else:
        print(f"[INFO] gate_story tags: {len(ms)}")

    if MARK not in s:
        s = "\n<!-- " + MARK + " -->\n" + s
        changed = True

    return s, changed

patched = []
for p in cands:
    s = p.read_text(encoding="utf-8", errors="replace")
    if not is_vsp5_renderer(s):
        continue

    print("[HIT] renderer candidate:", p)
    backup(p)

    s2, ch = patch_text(s)
    if ch:
        p.write_text(s2, encoding="utf-8")
        patched.append(str(p))
        print("[OK] patched:", p)
    else:
        print("[OK] no change needed:", p)

if not patched:
    # fallback: brute search the exact duplicate snippet by only gate_story occurrences
    print("[WARN] no renderer matched bundle+luxe. fallback: patch file having >=2 gate_story tags")
    for p in cands:
        s = p.read_text(encoding="utf-8", errors="replace")
        ms = list(gate_pat.finditer(s))
        if len(ms) >= 2:
            print("[HIT][fallback] dup gate_story:", p, "count=", len(ms))
            backup(p)
            s2, ch = patch_text(s)
            if ch:
                p.write_text(s2, encoding="utf-8")
                patched.append(str(p))
                print("[OK] patched:", p)
            break

print("[DONE] patched_files=", patched)
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
