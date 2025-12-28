#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
CSS="static/css/vsp_dashboard_polish_v1.css"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_dashfix_${TS}"
echo "[BACKUP] ${WSGI}.bak_dashfix_${TS}"

mkdir -p "$(dirname "$CSS")"
cat > "$CSS" <<'CSS'
/* VSP_DASHBOARD_POLISH_V1 (Dashboard-only cosmetics; safe globals) */
:root{
  --bg0: #070e1a;
  --bg1: #0b1220;
  --bg2: rgba(255,255,255,.06);
  --line: rgba(255,255,255,.10);
  --txt: rgba(226,232,240,.92);
  --muted: rgba(148,163,184,.85);
  --accent: rgba(56,189,248,.88);
  --accent2: rgba(168,85,247,.66);
  --shadow: 0 12px 30px rgba(0,0,0,.38);
  --r: 16px;
}

html,body{ background: linear-gradient(180deg, var(--bg0), var(--bg1)); color: var(--txt); }
*{ box-sizing:border-box; }
a{ color: var(--txt); }
a:hover{ color: rgba(255,255,255,.98); }

#vsp5_root{
  padding: 14px 16px;
  max-width: 1480px;
  margin: 0 auto;
}

/* nice scrollbars (webkit) */
::-webkit-scrollbar{ width: 10px; height: 10px; }
::-webkit-scrollbar-thumb{ background: rgba(255,255,255,.14); border-radius: 12px; }
::-webkit-scrollbar-thumb:hover{ background: rgba(255,255,255,.22); }

/* “card-ish” common selectors (best effort) */
.card, .panel, .box, .kpi, .tile, .vsp-card, .vsp_panel, .vsp_kpi{
  border: 1px solid var(--line);
  border-radius: var(--r);
  background: rgba(0,0,0,.18);
  box-shadow: 0 6px 18px rgba(0,0,0,.22);
  backdrop-filter: blur(8px);
}

/* buttons / pills common */
button, .btn, .pill, .chip, .tag{
  border-radius: 999px;
  border: 1px solid rgba(255,255,255,.14);
  background: rgba(255,255,255,.05);
  color: var(--txt);
}
button:hover, .btn:hover, .pill:hover, .chip:hover, .tag:hover{
  background: rgba(255,255,255,.08);
  border-color: rgba(255,255,255,.20);
}

/* subtle focus */
:focus{ outline: none; }
:focus-visible{
  outline: 2px solid rgba(56,189,248,.40);
  outline-offset: 2px;
}

/* gradient accent line for headers if exist */
h1,h2,h3,.title,.hdr,.header{
  text-shadow: 0 8px 22px rgba(0,0,0,.35);
}
CSS
echo "[OK] wrote $CSS"

python3 - <<'PY'
from pathlib import Path
import re

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_DASH_FIX_BOOT_CSS_DEDUPE_QUIET_CACHEHOT_V1"
if MARK in s:
    print("[OK] marker already present")
else:
    # 1) ensure /vsp5 HTML HEAD includes polish css
    # Try to inject a <link ...polish...> right after <title>VSP5</title> or after <meta ...Expires...>
    if "vsp_dashboard_polish_v1.css" not in s:
        # best-effort injection: locate the literal HTML snippet for /vsp5 (we saw <title>VSP5</title>)
        s = re.sub(
            r'(<title>\s*VSP5\s*</title>\s*)',
            r'\1  <link rel="stylesheet" href="/static/css/vsp_dashboard_polish_v1.css"/>\n',
            s,
            flags=re.I
        )

    # 2) dedupe gate_story script if the /vsp5 html accidentally contains it twice
    # Keep first occurrence, drop any later duplicate occurrences in the same HTML string.
    # We do this by collapsing consecutive duplicates pattern in the big HTML literal.
    s = re.sub(
        r'(<script\s+src="/static/js/vsp_dashboard_gate_story_v1\.js[^"]*"></script>\s*){2,}',
        r'\1',
        s,
        flags=re.I
    )

    # 3) quiet cachehot "endpoint NOT FOUND" spam: gate printing behind env flag
    # Replace print(...) lines safely (only those exact messages).
    def gate_print(m):
        line = m.group(0)
        # indent preserved
        indent = re.match(r'^(\s*)', line).group(1)
        return f'{indent}import os\n{indent}if os.environ.get("VSP_CACHEHOT_DEBUG",""):\n{indent}  {line.strip()}\n'

    # if there are explicit print lines, wrap them
    for pat in [
        r'^\s*print\(\s*"\[VSP\]\s*cachehot:\s*endpoint\s*NOT\s*FOUND[^"]*"\s*\)\s*$',
        r"^\s*print\(\s*'\[VSP\]\s*cachehot:\s*endpoint\s*NOT\s*FOUND[^']*'\s*\)\s*$",
    ]:
        s = re.sub(pat, gate_print, s, flags=re.M)

    # 4) Add a top marker comment (so we know this patch is active)
    s = "\n# ===================== " + MARK + " =====================\n" + s

    w.write_text(s, encoding="utf-8")
    print("[OK] patched wsgi with marker + boot css + dedupe + quiet cachehot")

PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 0.6

echo "== verify /vsp5 contains polish css + gate_story count =="
HTML="$(curl -fsS "$BASE/vsp5" || true)"
echo "$HTML" | grep -n "vsp_dashboard_polish_v1.css" || echo "[WARN] polish css not found in /vsp5 HTML"
CNT="$(echo "$HTML" | grep -o "vsp_dashboard_gate_story_v1.js" | wc -l | tr -d ' ')"
echo "[INFO] gate_story occurrences in /vsp5 HTML = $CNT"

echo "[DONE] Now hard refresh /vsp5 (Ctrl+Shift+R)"
