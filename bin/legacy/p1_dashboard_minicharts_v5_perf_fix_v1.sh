#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_v5perf_${TS}"
echo "[BACKUP] ${JS}.bak_v5perf_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_DASH_MINICHARTS_RENDERBARS_V5"
i=s.find(marker)
if i < 0:
    raise SystemExit("[ERR] V5 marker not found; patch V5 first")

tail=s[i:]

# 1) replace findHeaderLike (heavy scan) -> fast version
pat_find = re.compile(r'function\s+findHeaderLike\s*\(\s*title\s*\)\s*\{.*?\n\s*\}\n', re.S)
m=pat_find.search(tail)
if not m:
    raise SystemExit("[ERR] could not locate findHeaderLike() in V5 block")

fast_find = r'''function findHeaderLike(title){
      const want = norm(title);
      // prefer headings only (cheap)
      const hs = Array.from(document.querySelectorAll("h1,h2,h3,h4,h5"));
      for(const e of hs){
        const t = norm(e.textContent);
        if(t === want || t.includes(want)) return e;
      }
      // fallback: TreeWalker over text nodes with early stop + cap
      try{
        const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
        let n=0, node=null;
        while((node = tw.nextNode())){
          n++; if(n>8000) break;
          const txt = norm(node.nodeValue || "");
          if(!txt) continue;
          if(txt === want || txt.includes(want)){
            return node.parentElement || null;
          }
        }
      }catch(e){}
      return null;
    }
'''
tail = tail[:m.start()] + fast_find + tail[m.end():]

# 2) replace readKPINum (super heavy div scan) -> fast TreeWalker
pat_kpi = re.compile(r'function\s+readKPINum\s*\(\s*label\s*\)\s*\{.*?\n\s*return\s+0\s*;\s*\n\s*\}\n', re.S)
m=pat_kpi.search(tail)
if not m:
    raise SystemExit("[ERR] could not locate readKPINum() in V5 block")

fast_kpi = r'''function readKPINum(label){
      const want = norm(label);
      // First: try common KPI card selectors (cheap)
      const sel = [
        "[data-kpi]", ".kpi", ".kpi-card", ".kpiCard", ".metric", ".metric-card",
        ".stat", ".stat-card", ".vsp-kpi", ".vsp-kpi-card"
      ].join(",");
      try{
        const nodes = document.querySelectorAll(sel);
        for(const el of nodes){
          const t = norm(el.textContent || "");
          if(!t.includes(want)) continue;
          const m = (el.textContent||"").match(/(\d{1,9})/);
          if(m) return parseInt(m[1],10);
        }
      }catch(e){}

      // Fallback: TreeWalker over text nodes, stop early, cap nodes
      try{
        const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
        let n=0, node=null;
        while((node = tw.nextNode())){
          n++; if(n>9000) break;
          const txt = norm(node.nodeValue || "");
          if(!txt) continue;
          if(!txt.includes(want)) continue;

          // walk up a few levels to find a nearby number (cap text length)
          let el = node.parentElement;
          for(let hop=0; hop<6 && el; hop++){
            const t = (el.textContent||"");
            const slice = t.length>600 ? t.slice(0,600) : t;
            const m = slice.match(/(\d{1,9})/);
            if(m) return parseInt(m[1],10);
            el = el.parentElement;
          }
          break;
        }
      }catch(e){}
      return 0;
    }
'''
tail = tail[:m.start()] + fast_kpi + tail[m.end():]

# write back whole file
s2 = s[:i] + tail
p.write_text(s2, encoding="utf-8")
print("[OK] V5 perf patch applied (findHeaderLike + readKPINum)")
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Ctrl+Shift+R: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5?rid=VSP_CI_20251218_114312"
grep -n "VSP_P1_DASH_MINICHARTS_RENDERBARS_V5" "$JS" | head -n 1 || true
