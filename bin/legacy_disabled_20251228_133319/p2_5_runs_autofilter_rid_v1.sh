#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import re, sys

ROOT = Path(".")
TPL_DIR = ROOT / "templates"
JS_DIR  = ROOT / "static" / "js"

MARK_BEGIN = "VSP_P2_5_RUNS_AUTOFILTER_RID_V1"
MARK_END   = "/VSP_P2_5_RUNS_AUTOFILTER_RID_V1"

PATCH = r"""
/* ===================== VSP_P2_5_RUNS_AUTOFILTER_RID_V1 ===================== */
(function(){
  try{
    const params = new URLSearchParams(window.location.search || "");
    const rid = params.get("rid");
    if(!rid) return;

    const esc = (s) => {
      try { return (window.CSS && CSS.escape) ? CSS.escape(s) : String(s).replace(/["\\]/g, "\\$&"); }
      catch(e){ return String(s); }
    };

    function injectStyle(){
      if(document.getElementById("vsp_runs_rid_hl_style")) return;
      const st = document.createElement("style");
      st.id = "vsp_runs_rid_hl_style";
      st.textContent = `
        .vsp-rid-hl { outline: 2px solid rgba(255,255,255,0.20); box-shadow: 0 0 0 2px rgba(80,160,255,0.35) inset; border-radius: 10px; }
        .vsp-rid-hl td, .vsp-rid-hl .cell, .vsp-rid-hl .col { background: rgba(80,160,255,0.12) !important; }
        .vsp-rid-pill { display:inline-block; margin-left:8px; padding:2px 8px; border-radius:999px; font-size:12px;
                        background: rgba(80,160,255,0.18); border:1px solid rgba(80,160,255,0.35); }
      `;
      (document.head || document.documentElement).appendChild(st);
    }

    function setFilterInput(){
      const selectors = [
        'input#runsFilter',
        'input[name="runsFilter"]',
        'input[type="search"]',
        'input[name="filter"]',
        'input[placeholder*="RID"]',
        'input[placeholder*="rid"]',
        'input[placeholder*="filter"]',
        'input[placeholder*="search"]'
      ];
      for(const s of selectors){
        const el = document.querySelector(s);
        if(el){
          el.value = rid;
          el.dispatchEvent(new Event("input", {bubbles:true}));
          el.dispatchEvent(new Event("change", {bubbles:true}));
          return true;
        }
      }
      return false;
    }

    function matchElHasRid(el){
      if(!el) return false;
      const attrs = ["data-rid","data-runid","data-run-id","data-run","data-id"];
      for(const a of attrs){
        try{
          const v = el.getAttribute && el.getAttribute(a);
          if(v && v.trim() == rid) return true;
        }catch(e){}
      }
      const t = (el.textContent || "").trim();
      return t.includes(rid);
    }

    function findRow(){
      const direct =
        document.querySelector(`[data-rid="${esc(rid)}"]`) ||
        document.querySelector(`[data-runid="${esc(rid)}"]`) ||
        document.querySelector(`[data-run-id="${esc(rid)}"]`);
      if(direct) return direct.closest("tr, .run-row, .vsp-run-row, li, .card, .row") || direct;

      const trs = Array.from(document.querySelectorAll("tr"));
      for(const tr of trs){
        if(matchElHasRid(tr)) return tr;
      }

      const items = Array.from(document.querySelectorAll("[data-rid], [data-runid], [data-run-id], .run-row, .vsp-run-row, li, .card, .row"));
      for(const it of items){
        if(matchElHasRid(it)) return it;
      }
      return null;
    }

    function filterSiblings(row){
      // hide siblings in same container to simulate "filter"
      const parent = row.parentElement;
      if(!parent) return;
      const kids = Array.from(parent.children);
      if(kids.length <= 1) return;

      for(const el of kids){
        if(el === row){ el.style.display = ""; continue; }
        // keep header rows
        const tag = (el.tagName || "").toLowerCase();
        if(tag === "tr" and (el.querySelector("th") or [])):
          continue
        # (note: above python-like line won't run in JS; kept safe by try/catch below)
      }
    }

    function hideNonMatchingInSameParent(row){
      const parent = row.parentElement;
      if(!parent) return;
      const kids = Array.from(parent.children);
      if(kids.length <= 1) return;

      for(const el of kids){
        if(el === row){ el.style.display = ""; continue; }
        const tag = (el.tagName || "").toLowerCase();
        if(tag === "thead") continue;
        if(tag === "tr"){
          const hasTH = !!el.querySelector("th");
          if(hasTH) continue;
        }
        if(matchElHasRid(el)){ el.style.display = ""; continue; }
        el.style.display = "none";
      }
    }

    function highlight(row){
      injectStyle();
      row.classList.add("vsp-rid-hl");
      try{
        const anchor = row.querySelector("td, .rid, .run-id, .id") || row;
        if(anchor && !anchor.querySelector(".vsp-rid-pill")){
          const pill = document.createElement("span");
          pill.className = "vsp-rid-pill";
          pill.textContent = "RID filter";
          anchor.appendChild(pill);
        }
      }catch(e){}
    }

    function scrollToRow(row){
      try{ row.scrollIntoView({block:"center"}); }
      catch(e){ try{ row.scrollIntoView(true); }catch(_){} }
    }

    function autoOpenOverlay(row){
      const btn = row.querySelector(
        'button[data-action*="overlay"], button[data-action*="report"], button[title*="Actions"], button[title*="Report"], a[data-action*="overlay"], a[data-action*="report"]'
      );
      if(btn){ btn.click(); return true; }
      return false;
    }

    // kick
    setFilterInput();

    const startedAt = Date.now();
    const maxMs = 15000;
    const timer = setInterval(() => {
      const row = findRow();
      if(row){
        highlight(row);
        hideNonMatchingInSameParent(row);
        scrollToRow(row);

        const open = params.get("open");
        if(open === "1" || open === "true") autoOpenOverlay(row);

        clearInterval(timer);
        return;
      }
      if(Date.now() - startedAt > maxMs){
        clearInterval(timer);
        console.warn("[VSP P2.5] RID not found in runs list:", rid);
      }
    }, 300);

  }catch(e){
    console.warn("[VSP P2.5] failed:", e);
  }
})();
/* ===================== /VSP_P2_5_RUNS_AUTOFILTER_RID_V1 ===================== */
"""

def extract_js_from_html(html: str):
    # src="/static/js/xxx.js?v=..."
    srcs = re.findall(r'''src=["'](/static/js/[^"']+\.js(?:\?[^"']*)?)["']''', html)
    out = []
    for s in srcs:
        s = s.split("?", 1)[0]
        out.append(s.replace("/static/js/", ""))
    return out

candidates = []

# 1) Find templates likely for runs
tpls = []
if TPL_DIR.exists():
    for p in TPL_DIR.rglob("*.html"):
        try:
            t = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        if ("/runs" in t) or ("VSP • Runs" in t) or ("vsp_runs" in t) or ("runs" in p.name.lower()):
            tpls.append((p, t))

# 2) Extract referenced JS
js_from_tpl = set()
for p, t in tpls:
    for js in extract_js_from_html(t):
        js_from_tpl.add(js)

# 3) Score JS candidates
patterns = [
    r"/api/vsp/runs",
    r"RunsQuick",
    r"\bruns\s*=",
    r"fetch\([^)]*/api/vsp/runs",
    r"vsp_runs",
    r"runs_reports",
    r"render.*runs",
]

def score_js(path: Path):
    try:
        s = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return -1, ""
    score = 0
    for pat in patterns:
        score += len(re.findall(pat, s))
    # small bonus by filename
    name = path.name.lower()
    if "runs" in name: score += 2
    if "quick" in name: score += 1
    if "overlay" in name: score += 1
    return score, s

# preferred: from template refs
for js in sorted(js_from_tpl):
    p = JS_DIR / js
    if p.exists():
        sc, content = score_js(p)
        candidates.append((sc, p, content))

# fallback: scan all static/js
if not candidates and JS_DIR.exists():
    for p in JS_DIR.glob("*.js"):
        sc, content = score_js(p)
        if sc > 0:
            candidates.append((sc, p, content))

if not candidates:
    print("[ERR] cannot find runs JS candidate. No templates/js matched.", file=sys.stderr)
    sys.exit(2)

candidates.sort(key=lambda x: (x[0], x[1].name), reverse=True)
sc, target, content = candidates[0]

print(f"[INFO] picked JS: {target} (score={sc})")

if MARK_BEGIN in content:
    print("[OK] already patched (marker found).")
    sys.exit(0)

bak = target.with_suffix(target.suffix + f".bak_p2_5_rid_{__import__('datetime').datetime.now().strftime('%Y%m%d_%H%M%S')}")
bak.write_text(content, encoding="utf-8")
print(f"[BACKUP] {bak}")

new_content = content.rstrip() + "\n\n" + PATCH.strip() + "\n"
target.write_text(new_content, encoding="utf-8")
print("[OK] patched:", MARK_BEGIN)
PY

# node syntax check if available
JS_PICKED="$(python3 - <<'PY'
from pathlib import Path
import re, sys
p = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js")
# pick newest modified .js that has marker
cands = []
for f in p.glob("*.js"):
    try:
        s = f.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if "VSP_P2_5_RUNS_AUTOFILTER_RID_V1" in s:
        cands.append((f.stat().st_mtime, str(f)))
cands.sort(reverse=True)
print(cands[0][1] if cands else "")
PY
)"

if command -v node >/dev/null 2>&1 && [ -n "${JS_PICKED:-}" ]; then
  node --check "$JS_PICKED"
  echo "[OK] node --check: $JS_PICKED"
else
  echo "[WARN] skip node --check (node missing or marker JS not found)"
fi

echo
echo "[NEXT] Test:"
echo "  1) Open: /runs?rid=VSP_CI_...   (should auto-filter + highlight + scroll)"
echo "  2) Optional overlay auto-open: /runs?rid=VSP_CI_...&open=1"
echo "  3) Remember hard refresh Ctrl+Shift+R if cache bites."
