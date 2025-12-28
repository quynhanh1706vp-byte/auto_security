#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node

TS="$(date +%Y%m%d_%H%M%S)"
GS="static/js/vsp_dashboard_gate_story_v1.js"
PJS="static/js/vsp_dashboard_commercial_panels_v1.js"

[ -f "$GS" ]  || { echo "[ERR] missing $GS"; exit 2; }
[ -f "$PJS" ] || { echo "[ERR] missing $PJS"; exit 2; }

cp -f "$GS"  "${GS}.bak_gateRid_${TS}"
cp -f "$PJS" "${PJS}.bak_gateRid_${TS}"
echo "[BACKUP] ${GS}.bak_gateRid_${TS}"
echo "[BACKUP] ${PJS}.bak_gateRid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

GS = Path("static/js/vsp_dashboard_gate_story_v1.js")
PJS = Path("static/js/vsp_dashboard_commercial_panels_v1.js")

# --- patch GateStory: set window.__VSP_GATE_RID once rid is resolved ---
s = GS.read_text(encoding="utf-8", errors="replace")
if "window.__VSP_GATE_RID" not in s:
    # insert right after setting #gs_rid
    pat = r'(q\("#gs_rid"\)\.textContent\s*=\s*`gate_root:\s*\$\{rid\}`;\s*)'
    rep = r'\1\n    window.__VSP_GATE_RID = rid;\n    window.__VSP_GATE_RID_TS = Date.now();\n'
    s2, n = re.subn(pat, rep, s, count=1)
    if n != 1:
        raise SystemExit("[ERR] cannot find insertion point for __VSP_GATE_RID in GateStory")
    GS.write_text(s2, encoding="utf-8")
    print("[OK] GateStory patched: set window.__VSP_GATE_RID")
else:
    print("[OK] GateStory already has window.__VSP_GATE_RID")

# --- patch Panels: prefer window.__VSP_GATE_RID + robust fetch + top findings sample ---
p = PJS.read_text(encoding="utf-8", errors="replace")

# replace getJSON to include http status
p = re.sub(
    r'async function getJSON\(\s*url\s*\)\s*\{\s*const r = await fetch\(url, \{credentials:"same-origin"\}\);\s*const t = await r\.text\(\);\s*try \{ return JSON\.parse\(t\); \} catch\(e\)\{ return \{ok:false, err:"bad_json", _text:t\.slice\(0,220\)\}; \}\s*\}',
    r'''async function getJSON(url){
    const r = await fetch(url, {credentials:"same-origin"});
    const t = await r.text();
    let j = null;
    try { j = JSON.parse(t); } catch(e){ j = {ok:false, err:"bad_json", _text:t.slice(0,220)}; }
    if (j && typeof j === "object"){
      j.__http_status = r.status;
      j.__http_ok = r.ok;
    }
    return j;
  }''',
    p,
    flags=re.S
)

# In main(): replace rid selection to prefer window.__VSP_GATE_RID
# Find: const rid = ridFromText();
p, n1 = re.subn(
    r'const rid\s*=\s*ridFromText\(\)\s*;',
    r'''let rid = (window.__VSP_GATE_RID && typeof window.__VSP_GATE_RID === "string") ? window.__VSP_GATE_RID : null;
    if (!rid) rid = ridFromText();''',
    p,
    count=1
)
if n1 != 1:
    print("[WARN] cannot replace ridFromText line (maybe already patched).")

# Add probe fallback if first rid gives 404/bad_json; try to re-pick from text
# We'll inject after building url
if "probe failed" not in p:
    p = p.replace(
        'const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`;\n    const raw = await getJSON(url);\n    const j = unwrap(raw);',
        'let url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`;\n    let raw = await getJSON(url);\n    let j = unwrap(raw);\n    if (!j){\n      // fallback: if RID came from stale text, try re-pick from page text\n      const rid2 = ridFromText();\n      if (rid2 && rid2 !== rid){\n        rid = rid2;\n        url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`;\n        raw = await getJSON(url);\n        j = unwrap(raw);\n      }\n    }'
    )

# Improve rendering: show real counts + top findings sample (best-effort)
if "function sevRank" not in p:
    insert = r'''
  function sevRank(f){
    const s = String((f && (f.severity_norm || f.severity_normalized || f.severity || (f.meta && f.meta.severity) || "")) || "").toUpperCase();
    const order = {CRITICAL:6, HIGH:5, MEDIUM:4, LOW:3, INFO:2, TRACE:1};
    return order[s] || 0;
  }
  function sevLabel(f){
    const s = String((f && (f.severity_norm || f.severity_normalized || f.severity || (f.meta && f.meta.severity) || "")) || "").toUpperCase();
    return s || "UNKNOWN";
  }
  function titleOf(f){
    return (f && (f.title || f.rule_name || f.rule_id || f.check_name || f.message || f.id || "")) ? String(f.title || f.rule_name || f.rule_id || f.check_name || f.message || f.id) : "finding";
  }
'''
    # insert before async function main(){
    p = re.sub(r'(async function main\(\)\{)', insert + r'\1', p, count=1)

# Replace body rendering section to fill summary + top findings
# We locate the block where it sets body.innerHTML = "" and adds cards; replace with richer content
p = re.sub(
    r'body\.innerHTML\s*=\s*"";\s*body\.appendChild\(card\("RID", rid\)\);\s*body\.appendChild\(card\("Findings total", String\(total\)\)\);\s*body\.appendChild\(card\("CRITICAL/HIGH", `\$\{c\.CRITICAL\|\|0\}/\$\{c\.HIGH\|\|0\}`\)\);\s*body\.appendChild\(card\("MED/LOW/INFO", `\$\{c\.MEDIUM\|\|0\}/\$\{c\.LOW\|\|0\}/\$\{c\.INFO\|\|0\}`\)\);\s*console\.log\("\[P1PanelsExtV1\].*?;\s*',
    r'''body.innerHTML = "";
    // Summary cards
    body.appendChild(card("RID", rid));
    body.appendChild(card("Findings total", String(total)));
    body.appendChild(card("CRITICAL/HIGH", `${c.CRITICAL||0}/${c.HIGH||0}`));
    body.appendChild(card("MED/LOW/INFO/TRACE", `${c.MEDIUM||0}/${c.LOW||0}/${c.INFO||0}/${c.TRACE||0}`));

    // Top findings sample (best-effort)
    const top = (Array.isArray(j.findings) ? j.findings.slice() : [])
      .sort((a,b)=> sevRank(b)-sevRank(a))
      .slice(0, 8);
    const box = document.createElement("div");
    box.style.gridColumn = "1 / -1";
    box.style.border = "1px solid rgba(255,255,255,.10)";
    box.style.borderRadius = "14px";
    box.style.padding = "10px 12px";
    box.style.background = "rgba(0,0,0,.18)";
    box.innerHTML = '<div style="font-size:12px;opacity:.85;margin-bottom:8px">Top Findings (sample)</div>';
    if (!top.length){
      box.innerHTML += '<div style="opacity:.8;font-size:12px">No findings (or not available).</div>';
    } else {
      const ul = document.createElement("div");
      ul.style.display="grid";
      ul.style.gap="6px";
      top.forEach(f=>{
        const row = document.createElement("div");
        row.style.fontSize="12px";
        row.style.opacity="0.95";
        row.textContent = `[${sevLabel(f)}] ${titleOf(f)}`.slice(0, 160);
        ul.appendChild(row);
      });
      box.appendChild(ul);
    }
    host.appendChild(box);

    console.log("[P1PanelsExtV1] rendered rid=", rid, "total=", total, "counts=", c);''',
    p,
    flags=re.S
)

PJS.write_text(p, encoding="utf-8")
print("[OK] Panels patched: prefer window.__VSP_GATE_RID + top findings")
PY

node --check "$GS"
node --check "$PJS"
echo "[OK] node --check GateStory + Panels OK"

echo
echo "[NEXT] restart UI then Ctrl+Shift+R /vsp5"
