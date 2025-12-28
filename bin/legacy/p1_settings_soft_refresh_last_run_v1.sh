#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] detect settings template + js =="
PYOUT="$(python3 - <<'PY'
from pathlib import Path
import re, json

tpl = None
js  = None

root = Path("templates")
if root.exists():
  # pick the first template that looks like Settings
  for p in root.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="ignore")
    if ("<title>VSP • Settings" in s) or ("/settings" in s and "Settings" in s):
      tpl = str(p)
      # find js includes
      m = re.findall(r'src=["\'](/static/js/[^"\']+\.js)[^"\']*["\']', s)
      if m:
        # choose last include (often the page script)
        js = m[-1].lstrip("/")
      break

print(json.dumps({"tpl": tpl, "js": js}))
PY
)"

TPL="$(python3 - <<PY
import json
print(json.loads('''$PYOUT''').get("tpl") or "")
PY
)"
JS="$(python3 - <<PY
import json
print(json.loads('''$PYOUT''').get("js") or "")
PY
)"

if [ -z "$JS" ] || [ ! -f "$JS" ]; then
  echo "[WARN] cannot detect settings page js from template. fallback to static/js/vsp_dash_only_v1.js"
  JS="static/js/vsp_dash_only_v1.js"
fi

[ -f "$JS" ] || { echo "[ERR] target js not found: $JS"; exit 2; }
echo "[OK] patch_js=$JS"

cp -f "$JS" "${JS}.bak_setsoft_${TS}"
echo "[BACKUP] ${JS}.bak_setsoft_${TS}"

export JS

python3 - <<'PY'
import os, re, textwrap
from pathlib import Path

p = Path(os.environ["JS"])
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_SETTINGS_SOFT_REFRESH_LASTRUN_V1"
if MARK in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

# Heuristic: locate any function that fetches rid_latest_gate_root or run_gate_summary
# We'll call it if found, else we do direct fetches here.
fn_names = re.findall(r"\basync function\s+([A-Za-z0-9_]+)\s*\(", s) + re.findall(r"\bfunction\s+([A-Za-z0-9_]+)\s*\(", s)
seen=set(); fns=[]
for n in fn_names:
  if n not in seen:
    seen.add(n); fns.append(n)

def pick_any(subs):
  for n in fns:
    low=n.lower()
    for ss in subs:
      if ss in low:
        return n
  return None

# Prefer explicit refresh functions if they exist
refresh_fn = pick_any(["settings","last","run","badge","status","refresh","load"])

addon = textwrap.dedent(f"""
/* ===================== {MARK} ===================== */
(()=> {{
  if (window.__vsp_p1_settings_soft_refresh_lastrun_v1) return;
  window.__vsp_p1_settings_soft_refresh_lastrun_v1 = true;

  function followOn(){{
    try {{ return (localStorage.getItem("vsp_follow_latest") ?? "on") !== "off"; }}
    catch(e) {{ return true; }}
  }}

  async function jget(u){{
    const r = await fetch(u, {{credentials:"same-origin"}});
    if (!r.ok) throw new Error("HTTP "+r.status);
    return await r.json();
  }}

  function setTextAny(selList, txt){{
    try {{
      for (const sel of selList){{
        const el = document.querySelector(sel);
        if (el) el.textContent = txt;
      }}
    }} catch(e) {{}}
  }}

  function setBadge(sel, clsAdd, clsRemove){{
    try {{
      const el = document.querySelector(sel);
      if (!el) return;
      if (clsRemove) el.classList.remove(clsRemove);
      if (clsAdd) el.classList.add(clsAdd);
    }} catch(e) {{}}
  }}

  async function refreshLastRunExplicit(rid){{
    // Update RID labels if any
    setTextAny(["#rid_txt","#rid_val","#rid_text","#rid_label","[data-vsp-rid]"], rid);

    // Pull gate summary (overall + counts)
    try {{
      const sum = await jget(`/api/vsp/run_file_allow?rid=${{encodeURIComponent(rid)}}&path=run_gate_summary.json`);
      if (sum && sum.ok) {{
        // Best-effort: fill common fields if exist
        if (sum.overall) setTextAny(["#overall","#overall_txt","#overall_val","[data-vsp-overall]"], String(sum.overall));
        if (sum.counts_total) {{
          const ct = sum.counts_total;
          if (ct.CRITICAL != null) setTextAny(["#c_critical","[data-vsp-c-critical]"], String(ct.CRITICAL));
          if (ct.HIGH != null)     setTextAny(["#c_high","[data-vsp-c-high]"], String(ct.HIGH));
          if (ct.MEDIUM != null)   setTextAny(["#c_medium","[data-vsp-c-medium]"], String(ct.MEDIUM));
          if (ct.LOW != null)      setTextAny(["#c_low","[data-vsp-c-low]"], String(ct.LOW));
          if (ct.INFO != null)     setTextAny(["#c_info","[data-vsp-c-info]"], String(ct.INFO));
          if (ct.TRACE != null)    setTextAny(["#c_trace","[data-vsp-c-trace]"], String(ct.TRACE));
        }}
      }}
    }} catch(e) {{
      // ignore
    }}
  }}

  async function doRefresh(rid){{
    // If there's an existing refresh function, call it; else do explicit minimal refresh
    {f"try {{ await {refresh_fn}(rid); return; }} catch(e) {{ /* fallback */ }}" if refresh_fn else "/* no detected refresh fn */"}
    await refreshLastRunExplicit(rid);
  }}

  window.addEventListener("vsp:rid_changed", (ev)=> {{
    try {{
      if (!followOn()) return;
      const d = ev && ev.detail ? ev.detail : null;
      const rid = d && d.rid ? d.rid : (window.__vsp_rid_latest||null);
      if (!rid) return;
      Promise.resolve(doRefresh(rid)).catch(()=>{{}});
    }} catch(e) {{}}
  }}, {{passive:true}});

}})();
/* ===================== /{MARK} ===================== */
""")

p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended Settings soft refresh hook; refresh_fn=", repr(refresh_fn))
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check passed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] settings soft refresh applied on $JS"
