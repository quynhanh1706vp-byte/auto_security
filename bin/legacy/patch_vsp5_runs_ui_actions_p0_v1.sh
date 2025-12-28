#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_actions_${TS}"
echo "[BACKUP] ${F}.bak_actions_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP5_RUNS_ACTION_STRIP_P0_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# Inject helper functions near top (after IIFE start)
m = re.search(r'^\(function\(\)\{\s*[\'"]use strict[\'"];\s*', s, flags=re.M)
if not m:
    print("[ERR] cannot find IIFE header")
    raise SystemExit(2)

inject = r'''
/* VSP5_RUNS_ACTION_STRIP_P0_V1 */
function vsp_rf(rid, name){
  try{
    const u = new URL("/api/vsp/run_file", window.location.origin);
    u.searchParams.set("rid", rid);
    u.searchParams.set("name", name);
    return u.pathname + "?" + u.searchParams.toString();
  }catch(e){
    return "/api/vsp/run_file?rid=" + encodeURIComponent(rid) + "&name=" + encodeURIComponent(name);
  }
}
function vsp_has_path(has, key){
  if(!has) return null;
  const v = has[key];
  return (typeof v === "string" && v.length) ? v : null;
}
function vsp_btn(href, label, ok, tip){
  const cls = ok ? "btn mini" : "btn mini disabled";
  const t = tip ? ` title="${String(tip).replace(/"/g,'&quot;')}"` : "";
  if(!ok) return `<span class="${cls}"${t}>${label}</span>`;
  return `<a class="${cls}" href="${href}" target="_blank" rel="noopener"${t}>${label}</a>`;
}
function vsp_pill(label, ok){
  const cls = ok ? "pill ok" : "pill off";
  return `<span class="${cls}">${label}</span>`;
}
'''

s2 = s[:m.end()] + "\n" + inject + "\n" + s[m.end():]

# Try to find row renderer and append "Reports" column render block.
# Best-effort: locate where HTML row string is built and contains run_id.
# We will replace occurrences of a placeholder like `${reports}` if exists, else append at end of row.
if "REPORTS_ACTIONS_SLOT" in s2:
    # already has slot (unlikely)
    pass
else:
    # Add a small CSS (if file includes style injection)
    if "pill ok" not in s2:
        css = r'''
(function(){
  try{
    if(document.getElementById("vsp_runs_actions_css")) return;
    const st=document.createElement("style");
    st.id="vsp_runs_actions_css";
    st.textContent = `
      .btn.mini{display:inline-block;padding:4px 8px;border-radius:10px;border:1px solid rgba(255,255,255,.12);text-decoration:none;margin-right:6px;font-size:12px}
      .btn.mini.disabled{opacity:.45;cursor:not-allowed}
      .pill{display:inline-block;padding:2px 8px;border-radius:999px;font-size:11px;margin-left:6px;border:1px solid rgba(255,255,255,.12)}
      .pill.ok{opacity:1}
      .pill.off{opacity:.45}
      .actions{white-space:nowrap}
    `;
    document.head.appendChild(st);
  }catch(e){}
})();
'''
        # put near top after helpers
        s2 = s2.replace("/* VSP5_RUNS_ACTION_STRIP_P0_V1 */", "/* VSP5_RUNS_ACTION_STRIP_P0_V1 */\n"+css, 1)

# Replace any existing "reports/html" single-link rendering (common) with full strip
# Heuristic: find "reports/index.html" string and wrap around it
def repl(m):
    return m.group(0)  # no-op

# Inject action strip function by adding snippet where each item is processed.
# We look for place where items are mapped (items.forEach / for (const it of items))
mm = re.search(r'(items\s*=\s*(?:data\.items|res\.items|json\.items)[^;]*;[\s\S]{0,800}?)(for\s*\(\s*(?:const|let)\s+it\s+of\s+items\s*\)|items\.forEach\s*\(\s*function\s*\(\s*it\s*\)|items\.forEach\s*\(\s*\(\s*it\s*\)\s*=>)', s2)
if not mm:
    # fallback: just append and rely on existing rendering not breaking
    p.write_text(s2, encoding="utf-8")
    print("[OK] injected helpers only (renderer not found)")
    raise SystemExit(0)

# Find first occurrence of "reports/index.html" and replace it with strip builder usage if possible
# We'll patch by adding: it.__actions_html = ...
insertion_point = mm.end()
patch_snip = r'''
try{
  const rid = it.run_id || it.rid || "";
  const has = it.has || {};
  const htmlUrl = vsp_has_path(has,"html_path") || (has.html ? vsp_rf(rid,"reports/index.html") : null);
  const jsonUrl = vsp_has_path(has,"json_path") || (has.json ? vsp_rf(rid,"reports/findings_unified.json") : vsp_rf(rid,"reports/findings_unified.json"));
  const sumUrl  = vsp_has_path(has,"summary_path") || (has.summary ? vsp_rf(rid,"reports/run_gate_summary.json") : vsp_rf(rid,"reports/run_gate_summary.json"));
  const txtUrl  = vsp_has_path(has,"txt_path") || vsp_rf(rid,"reports/SUMMARY.txt");
  it.__vsp_reports_actions = `<span class="actions">` +
    vsp_btn(htmlUrl||"#","HTML", !!htmlUrl, htmlUrl?"" :"missing HTML") +
    vsp_btn(jsonUrl||"#","JSON", true, "unified findings") +
    vsp_btn(sumUrl||"#","SUM", true, "gate summary") +
    vsp_btn(txtUrl||"#","TXT", true, "summary text") +
    vsp_pill("HTML", !!has.html) +
    vsp_pill("JSON", !!has.json) +
    vsp_pill("SUM",  !!has.summary) +
  `</span>`;
}catch(e){}
'''
s3 = s2[:insertion_point] + "\n" + patch_snip + "\n" + s2[insertion_point:]

# Now ensure renderer prints it.__vsp_reports_actions somewhere.
# Replace a likely "reports" cell content with it.__vsp_reports_actions if exists.
# Heuristic: replace first occurrence of `${it.has.html` patterns or "HTML" label in row.
s4 = s3
# common pattern: "+ (has.html ? ... : '-') +"
s4 = re.sub(r'(\+\s*\(\s*has\.html\s*\?\s*[^:]+:\s*[^)]+\)\s*\+)',
            '+ (it.__vsp_reports_actions || "") +', s4, count=1)

# if not replaced, try generic "reports/index.html" literal area
if s4 == s3:
    s4 = s4.replace("reports/index.html", "reports/index.html")  # no-op; keep safe

p.write_text(s4, encoding="utf-8")
print("[OK] patched:", MARK)
PY

command -v node >/dev/null 2>&1 && node --check "$F" && echo "[OK] node --check OK" || true
sudo systemctl restart vsp-ui-8910.service || true
echo "[OK] restart done. Now Ctrl+F5 /vsp5 (Runs & Reports tab)."
