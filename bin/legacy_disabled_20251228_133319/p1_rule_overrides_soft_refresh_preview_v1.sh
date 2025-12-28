#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] detect rule_overrides template + js =="
PYOUT="$(python3 - <<'PY'
from pathlib import Path
import re, json

tpl = None
js  = None

root = Path("templates")
if root.exists():
  for p in root.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="ignore")
    # identify rule overrides page
    if ("rule_overrides" in s and ("Rule Overrides" in s or "Overrides" in s)) or ("/rule_overrides" in s):
      tpl = str(p)
      m = re.findall(r'src=["\'](/static/js/[^"\']+\.js)[^"\']*["\']', s)
      if m:
        js = m[-1].lstrip("/")
      break

print(json.dumps({"tpl": tpl, "js": js}))
PY
)"

JS="$(python3 - <<PY
import json
print(json.loads('''$PYOUT''').get("js") or "")
PY
)"

if [ -z "$JS" ] || [ ! -f "$JS" ]; then
  echo "[WARN] cannot detect rule_overrides page js from template. fallback to static/js/vsp_dashboard_commercial_v1.js"
  JS="static/js/vsp_dashboard_commercial_v1.js"
fi

[ -f "$JS" ] || { echo "[ERR] target js not found: $JS"; exit 2; }
echo "[OK] patch_js=$JS"

cp -f "$JS" "${JS}.bak_rosf_${TS}"
echo "[BACKUP] ${JS}.bak_rosf_${TS}"

export JS

python3 - <<'PY'
import os, re, textwrap
from pathlib import Path

p = Path(os.environ["JS"])
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RULE_OVERRIDES_SOFT_REFRESH_PREVIEW_V1"
if MARK in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

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

# Try to find a preview/impact refresh function if exists
preview_fn = pick_any(["preview","impact","apply","calc","evaluate","refresh"])
# If no function exists, we do minimal fetch if there's a known endpoint reference in JS
has_preview_api = "/api/vsp/" in s and ("preview" in s.lower() or "impact" in s.lower())

addon = textwrap.dedent(f"""
/* ===================== {MARK} ===================== */
(()=> {{
  if (window.__vsp_p1_rule_overrides_soft_preview_v1) return;
  window.__vsp_p1_rule_overrides_soft_preview_v1 = true;

  function followOn(){{
    try {{ return (localStorage.getItem("vsp_follow_latest") ?? "on") !== "off"; }}
    catch(e) {{ return true; }}
  }}

  async function jget(u){{
    const r = await fetch(u, {{credentials:"same-origin"}});
    if (!r.ok) throw new Error("HTTP "+r.status);
    return await r.json();
  }}

  function setRidLabel(rid){{
    try {{
      const el = document.querySelector("#rid_txt,#rid_val,#rid_text,#rid_label,[data-vsp-rid]");
      if (el) el.textContent = rid;
    }} catch(e) {{}}
  }}

  async function refreshPreview(rid){{
    // If project already has a preview fn, use it.
    {f"try {{ await {preview_fn}(rid); return; }} catch(e) {{ /* fallback */ }}" if preview_fn else "/* no detected preview fn */"}

    // Minimal best-effort: if there is a preview panel element, at least show RID
    try {{
      const box = document.querySelector("#preview,#impact,#preview_box,#impact_box,[data-vsp-preview]");
      if (box) {{
        box.setAttribute("data-vsp-rid", rid);
      }}
    }} catch(e) {{}}

    // Optional: if your JS already references a preview endpoint, keep it as future extension
    { "/* preview endpoint appears referenced in bundle; leaving explicit fetch to existing functions */" if has_preview_api else "" }
  }}

  window.addEventListener("vsp:rid_changed", (ev)=> {{
    try {{
      if (!followOn()) return;
      const d = ev && ev.detail ? ev.detail : null;
      const rid = d && d.rid ? d.rid : (window.__vsp_rid_latest||null);
      if (!rid) return;
      setRidLabel(rid);
      Promise.resolve(refreshPreview(rid)).catch(()=>{{}});
    }} catch(e) {{}}
  }}, {{passive:true}});
}})();
/* ===================== /{MARK} ===================== */
""")

p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended Rule Overrides soft refresh hook; preview_fn=", repr(preview_fn))
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check passed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] rule_overrides soft refresh applied on $JS"
