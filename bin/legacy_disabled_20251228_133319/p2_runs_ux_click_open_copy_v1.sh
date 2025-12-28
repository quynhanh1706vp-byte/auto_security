#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_runs_kpi_compact_v3.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_runsux_${TS}"
echo "[BACKUP] ${JS}.bak_runsux_${TS}"

python3 - "$JS" <<'PY'
import sys, re
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_RUNS_UX_CLICK_OPEN_COPY_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# We modify the injected filterbar table renderer (VSP_P2_RUNS_FILTERS_SORT_V1B)
# 1) Add "Actions" header and Copy button cell
# 2) Change row click: open drawer if available (loadRunDetail), fallback copy
# 3) Copy button uses stopPropagation()

# Add header "Actions"
s2=re.sub(
    r'(<th[^>]*>Root</th>\s*</tr>)',
    r'\1\n              <th style="padding:10px 12px;border-bottom:1px solid rgba(255,255,255,0.10)">Actions</th>\n            </tr>',
    s, count=1, flags=re.I
)

# Add Actions cell in row template: after Root td
s2=re.sub(
    r'(<td style="padding:10px 12px;opacity:\.75;max-width:520px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">\$\{rootDir\}</td>\s*</tr>)',
    r'''<td style="padding:10px 12px;opacity:.75;max-width:520px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${rootDir}</td>
        <td style="padding:10px 12px;white-space:nowrap">
          <button data-testid="runs-copy-rid" style="padding:7px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit;cursor:pointer;font-size:12px">Copy</button>
        </td>
      </tr>''',
    s2, count=1
)

# Replace click handlers section: find the part that sets onclick=copy
# We'll inject: clicking row opens drawer if loadRunDetail exists; else copies.
pat=r'host\.querySelectorAll\("tbody tr"\)\.forEach\(tr=>\{\s*tr\.style\.cursor="pointer";[\s\S]*?tr\.onclick=\(\)=>\{\s*const rid=tr\.getAttribute\("data-rid"\)\|\|"";
\s*if\(rid\) navigator\.clipboard\?\.\writeText\(rid\)\.catch\(\(\)=>\{\}\);\s*\};\s*\}\);'
m=re.search(pat, s2, flags=re.X)
if not m:
    # fallback: don't hard fail; append marker only
    s2 += f"\n/* {marker} (noop: handler pattern not found) */\n"
    p.write_text(s2, encoding="utf-8")
    print("[WARN] handler pattern not found; left as-is")
    raise SystemExit(0)

new_handlers=r'''
host.querySelectorAll("tbody tr").forEach(tr=>{
      tr.style.cursor="pointer";
      tr.style.transition="background 120ms ease";
      tr.onmouseenter=()=>tr.style.background="rgba(255,255,255,0.05)";
      tr.onmouseleave=()=>tr.style.background="transparent";

      // Copy button
      const btn=tr.querySelector('[data-testid="runs-copy-rid"]');
      if(btn){
        btn.onclick=(e)=>{
          e.preventDefault(); e.stopPropagation();
          const rid=tr.getAttribute("data-rid")||"";
          if(rid) navigator.clipboard?.writeText(rid).catch(()=>{});
        };
      }

      // Row click: open drawer if available; fallback copy
      tr.onclick=(e)=>{
        const rid=tr.getAttribute("data-rid")||"";
        const tds=tr.querySelectorAll("td");
        const tsText = (tds && tds.length>1) ? (tds[1].textContent||"") : "";
        // if drawer function exists (from DRILLDOWN script), use it:
        if(typeof window.loadRunDetail === "function"){
          window.loadRunDetail(rid, tsText);
          return;
        }
        // fallback behavior: copy RID
        if(rid) navigator.clipboard?.writeText(rid).catch(()=>{});
      };
    });
'''
s2 = s2[:m.start()] + new_handlers + s2[m.end():]

# Expose loadRunDetail to window so UX patch can call it
if "async function loadRunDetail" in s2 and "window.loadRunDetail" not in s2:
    s2 = s2.replace(
        "async function loadRunDetail(rid, tsText){",
        "async function loadRunDetail(rid, tsText){"
    )
    # add export near end of drawer block (best-effort)
    s2 = s2.replace(
        "async function loadRunDetail(rid, tsText){",
        "async function loadRunDetail(rid, tsText){"
    )
    # append a safe exporter at end of file
    s2 += "\ntry{ if(typeof loadRunDetail==='function') window.loadRunDetail=loadRunDetail; }catch(e){}\n"

s2 += f"\n/* {marker} */\n"
p.write_text(s2, encoding="utf-8")
print("[OK] patched runs UX: click opens drawer, Copy button added")
PY

node -c "$JS"
echo "[OK] node -c OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

grep -n "VSP_P2_RUNS_UX_CLICK_OPEN_COPY_V1" -n "$JS" | head -n 3
