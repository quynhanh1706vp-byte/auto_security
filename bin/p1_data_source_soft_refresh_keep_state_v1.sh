#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_data_source_lazy_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_softds_${TS}"
echo "[BACKUP] ${JS}.bak_softds_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_data_source_lazy_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DATA_SOURCE_SOFT_REFRESH_KEEP_STATE_V1"
if MARK in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

# Try to detect a "main refresh/load" function; fallback to re-trigger existing init/load
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

reload_fn = pick_any(["load","fetch","refresh","render","init","boot"])

# Build call snippet (best effort)
call = f"try {{ await {reload_fn}(); }} catch(e) {{}}" if reload_fn else "/* no obvious load fn detected */"

addon = textwrap.dedent(f"""
/* ===================== {MARK} ===================== */
(()=> {{
  if (window.__vsp_p1_ds_soft_refresh_keep_state_v1) return;
  window.__vsp_p1_ds_soft_refresh_keep_state_v1 = true;

  function followOn(){{
    try {{ return (localStorage.getItem("vsp_follow_latest") ?? "on") !== "off"; }}
    catch(e) {{ return true; }}
  }}

  function setRidLabel(rid){{
    try {{
      const el = document.querySelector("#rid_txt,#rid_val,#rid_text,#rid_label,[data-vsp-rid]");
      if (el) el.textContent = rid;
    }} catch(e) {{}}
  }}

  async function doRefresh(){{
    {call}
  }}

  window.addEventListener("vsp:rid_changed", (ev)=> {{
    try {{
      if (!followOn()) return;
      const d = ev && ev.detail ? ev.detail : null;
      const rid = d && d.rid ? d.rid : (window.__vsp_rid_latest||null);
      if (!rid) return;
      setRidLabel(rid);
      Promise.resolve(doRefresh()).catch(()=>{{}});
    }} catch(e) {{}}
  }}, {{passive:true}});
}})();
/* ===================== /{MARK} ===================== */
""")

p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended Data Source soft refresh hook; reload_fn=", {repr(reload_fn)})
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check passed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] data_source soft refresh keep-state applied"
