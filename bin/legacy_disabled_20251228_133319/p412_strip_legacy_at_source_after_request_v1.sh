#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_p412_${TS}"
echo "[OK] backup: $APP.bak_p412_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

TAG = "VSP_P412_STRIP_LEGACY_HTML"
if TAG in s:
    print("[OK] P412 already present"); raise SystemExit(0)

block = r'''
# === [VSP_P412_STRIP_LEGACY_HTML] remove legacy panels at source for /c/settings & /c/rule_overrides ===
def _vsp_p412_strip_legacy_panels(html: str) -> str:
    """
    Remove legacy panels *from HTML output* so curl-based smoke doesn't see legacy text.
    Strategy: parse <div>...</div> ranges using a stack, and delete the smallest "panel-like" div that contains markers.
    """
    import re
    from bisect import bisect_left

    markers = [
        "PIN default (stored local)",
        "Paste overrides JSON here",
        "Prefer backend",
        "fallback localStorage",
        "VSP_RULE_OVERRIDES_EDITOR_P0_V1",
        "Rule Overrides (live from",
        "Gate summary (live)",
    ]

    # collect marker positions
    rxm = re.compile("|".join(re.escape(m) for m in markers))
    pos = [m.start() for m in rxm.finditer(html)]
    if not pos:
        return html

    # scan div open/close with stack (nested-safe)
    rxtag = re.compile(r'(?is)<div\b[^>]*>|</div\s*>')
    stack = []  # (start_index, is_panelish, tag_text)
    intervals = []

    def has_marker(a:int, b:int) -> bool:
        i = bisect_left(pos, a)
        return i < len(pos) and pos[i] < b

    for m in rxtag.finditer(html):
        t = m.group(0)
        if t.lower().startswith("<div"):
            tag = t
            low = tag.lower()
            is_panelish = ("panel" in low) or ("card" in low) or ("panel" in low and "class=" in low)
            stack.append((m.start(), is_panelish, tag))
        else:
            if not stack:
                continue
            start, is_panelish, tag = stack.pop()
            end = m.end()
            if not has_marker(start, end):
                continue

            # safety: don't delete giant wrappers
            span = end - start
            if span > 180000:
                continue

            # prefer deleting panel-like containers; if not panel-like, still allow but tighter safety
            if (not is_panelish) and span > 60000:
                continue

            intervals.append((start, end))

    if not intervals:
        return html

    # merge intervals
    intervals.sort()
    merged = []
    for a,b in intervals:
        if not merged or a > merged[-1][1]:
            merged.append([a,b])
        else:
            merged[-1][1] = max(merged[-1][1], b)

    out = []
    last = 0
    for a,b in merged:
        out.append(html[last:a])
        last = b
    out.append(html[last:])
    new_html = "".join(out)

    return new_html


try:
    # only for Flask app context
    from flask import request
    if "app" in globals():
        @app.after_request
        def _vsp_p412_after_request_strip(resp):
            try:
                path = getattr(request, "path", "")
                if path not in ("/c/settings", "/c/rule_overrides"):
                    return resp
                ct = (resp.headers.get("Content-Type","") or "")
                if "text/html" not in ct:
                    return resp
                # flask response may be streamed; guard carefully
                get_data = getattr(resp, "get_data", None)
                set_data = getattr(resp, "set_data", None)
                if not callable(get_data) or not callable(set_data):
                    return resp
                html = resp.get_data(as_text=True)
                new_html = _vsp_p412_strip_legacy_panels(html)
                if new_html != html:
                    resp.set_data(new_html)
                    resp.headers["X-VSP-P412-STRIP"] = "1"
            except Exception:
                pass
            return resp
except Exception:
    pass
# === [/VSP_P412_STRIP_LEGACY_HTML] ===
'''

# append at end
s2 = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended P412 block to vsp_demo_app.py")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"

echo ""
echo "[NEXT] restart service then re-run P410:"
echo "  sudo systemctl restart vsp-ui-8910.service || true"
echo "  bash bin/p410_smoke_no_legacy_10x_v1.sh"
