#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

MARK="VSP_UI_KEEPALIVE_TB_AND_THEME_P1_V1"
tpl_root = Path("templates")
if not tpl_root.is_dir():
    raise SystemExit("[ERR] templates/ not found")

# target templates that likely contain the runs table / tb element
cands = []
for p in tpl_root.rglob("*.html"):
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if 'id="tb"' in s or "id='tb'" in s:
        cands.append(p)

# If not found, still try to patch vsp5 main template(s)
fallback = []
for name in ["vsp5.html","vsp5_2025.html","runs.html","vsp_runs.html","vsp_dashboard_2025.html","base.html","layout.html","index.html"]:
    p = tpl_root / name
    if p.exists():
        fallback.append(p)

targets = list(dict.fromkeys(cands + fallback))
if not targets:
    raise SystemExit("[ERR] no template targets found")

css = r"""
/* VSP_UI_THEME_STABLE_P1_V1 */
:root{
  --vsp-fg:#e6e6e6; --vsp-muted:#b7b7b7; --vsp-bg:#0f1115;
  --vsp-card:#141823; --vsp-border:#252c3a;
  --vsp-accent:#7aa2f7;
}
html,body{ background:var(--vsp-bg); color:var(--vsp-fg); }
body{ font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, "Helvetica Neue", Arial; }
a{ color:var(--vsp-accent); }
table{ border-color:var(--vsp-border); }
th,td{ border-color:var(--vsp-border) !important; }
textarea,input,select{
  background:#0c0f16 !important;
  color:var(--vsp-fg) !important;
  border:1px solid var(--vsp-border) !important;
  outline:none !important;
}
textarea:focus,input:focus,select:focus{
  border-color:var(--vsp-accent) !important;
  box-shadow:none !important;
}
.vsp-card, .card, .panel{
  background:var(--vsp-card);
  border:1px solid var(--vsp-border);
  border-radius:12px;
}
"""

js = r"""
/* VSP_UI_KEEPALIVE_TB_P1_V1 */
(() => {
  try{
    if (window.__vsp_keepalive_tb_p1_v1) return;
    window.__vsp_keepalive_tb_p1_v1 = true;

    function attach(){
      const tb = document.getElementById("tb");
      if (!tb) return false;

      let lastGood = "";
      let restoring = false;

      const good = (html) => {
        if (!html) return false;
        const t = String(html).replace(/\s+/g," ").trim();
        return t.length >= 80 && !/loading/i.test(t);
      };

      // seed
      if (good(tb.innerHTML)) lastGood = tb.innerHTML;

      const mo = new MutationObserver(() => {
        if (restoring) return;
        const cur = tb.innerHTML || "";
        if (good(cur)) {
          lastGood = cur;
          return;
        }
        // if became blank/too-small after previously good => restore
        if (lastGood && String(cur).replace(/\s+/g," ").trim().length < 20) {
          restoring = true;
          setTimeout(() => {
            try{
              tb.innerHTML = lastGood;
            }catch(_){}
            restoring = false;
          }, 60);
        }
      });

      mo.observe(tb, { childList:true, subtree:true, characterData:true });

      // also guard periodic clears (some render loops do tb.innerHTML="")
      setInterval(() => {
        try{
          const cur = tb.innerHTML || "";
          if (lastGood && String(cur).replace(/\s+/g," ").trim().length < 20) {
            tb.innerHTML = lastGood;
          }
        }catch(_){}
      }, 1500);

      return true;
    }

    // retry attach for SPA-ish pages
    let tries = 0;
    const t = setInterval(() => {
      tries++;
      if (attach() || tries > 40) clearInterval(t);
    }, 250);

  }catch(_){}
})();
"""

inject = f"""
<!-- {MARK} -->
<style id="{MARK}_CSS">{css}</style>
<script id="{MARK}_JS">{js}</script>
<!-- /{MARK} -->
"""

patched = []
for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        continue

    # inject before </body> if possible, else append
    if re.search(r"</body\s*>", s, flags=re.I):
        s2 = re.sub(r"(</body\s*>)", inject + r"\n\1", s, flags=re.I)
    else:
        s2 = s + "\n" + inject + "\n"

    bak = Path(str(p) + f".bak_keepalive_tb_theme_{int(time.time())}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s2, encoding="utf-8")
    patched.append(str(p))

print("[OK] patched files:")
for x in patched:
    print(" -", x)
if not patched:
    print("[OK] nothing to patch (marker already present everywhere)")
PY

echo "[NEXT] restart UI then Ctrl+F5:"
echo "  sudo systemctl restart vsp-ui-8910.service  # if you use systemd"
echo "  # or your existing restart script, then open /runs and /vsp5"
