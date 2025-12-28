#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_v1d_${TS}"
echo "[BACKUP] ${JS}.bak_v1d_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# -------------------------
# [1] FIX: recursion loop in VSP_P1_SOFT_REFRESH_CORE_V1
# Replace block to NOT dispatch vsp:rid_changed again.
# -------------------------
core_pat = re.compile(
  r"/\*\s*=+ VSP_P1_SOFT_REFRESH_CORE_V1 =+\s*\*/.*?/\*\s*=+\s*/VSP_P1_SOFT_REFRESH_CORE_V1\s*=+\s*\*/",
  re.S
)

safe_core = r"""/* ===================== VSP_P1_SOFT_REFRESH_CORE_V1 ===================== */
try {
  var __follow = (localStorage.getItem("vsp_follow_latest") ?? "on");
  // NOTE: DO NOT dispatch vsp:rid_changed here (this code may run inside rid_changed handler).
  if (__follow !== "off" && typeof window.__vsp_soft_refresh_apply === "function") {
    var __handled = false;
    try { __handled = !!window.__vsp_soft_refresh_apply((window.__vsp_rid_latest||null), (window.__vsp_rid_prev||null)); } catch(e) { __handled = false; }
    if (__handled) { /* handled => no reload */ }
    else { location.reload(); }
  } else {
    location.reload();
  }
} catch(e) { location.reload(); }
/* ===================== /VSP_P1_SOFT_REFRESH_CORE_V1 ===================== */"""

if "VSP_P1_SOFT_REFRESH_CORE_V1" in s:
  s2, n = core_pat.subn(safe_core, s, count=1)
  if n == 0:
    # If regex fails, do a smaller targeted removal of dispatchEvent on vsp:rid_changed
    s2 = re.sub(r"var __ev = new CustomEvent\(\"vsp:rid_changed\".*?window\.dispatchEvent\(__ev\);\s*\}\s*catch\(e\)\s*\{\s*\}\s*", "", s, flags=re.S)
    n = 1 if s2 != s else 0
  s = s2
  print(f"[OK] core loop guard applied (replaced core block) n={n}")
else:
  print("[WARN] core marker not found; skip core loop fix")

# -------------------------
# [2] Add real soft refresh apply for /vsp5
# Strategy:
# - find existing functions in file that already fetch/render (gate/findings/kpi/chart)
# - wire window.__vsp_soft_refresh_apply to update state.rid and call those functions
# - if cannot detect any refreshable functions => return false (so fallback reload works)
# -------------------------
MARK = "VSP_P1_VSP5_SOFT_REFRESH_APPLY_V1D"
if MARK in s:
  print("[SKIP] soft refresh apply already installed")
  p.write_text(s, encoding="utf-8")
  raise SystemExit(0)

# Collect candidate function names
fn_names = re.findall(r"\basync function\s+([A-Za-z0-9_]+)\s*\(", s)
fn_names += re.findall(r"\bfunction\s+([A-Za-z0-9_]+)\s*\(", s)
# unique preserve order
seen=set(); fns=[]
for n in fn_names:
  if n not in seen:
    seen.add(n); fns.append(n)

def pick(preds):
  for n in fns:
    low=n.lower()
    ok=True
    for pr in preds:
      if pr not in low:
        ok=False; break
    if ok:
      return n
  return None

gate_fn = pick(["gate","sum"]) or pick(["gate","summary"]) or pick(["gate"])
find_fn = pick(["find"]) or pick(["top","find"]) or pick(["finding"])
kpi_fn  = pick(["kpi"]) or pick(["stats"]) or pick(["count"])
chart_fn= pick(["chart"]) or pick(["plot"]) or pick(["trend"])
poll_fn = pick(["poll"]) or pick(["tick"]) or pick(["refresh"]) or pick(["update"])

# We also look for helper render/paint function
render_fn = pick(["render"]) or pick(["paint"]) or pick(["draw"])

# Decide capability: any of these exists
cap = any([gate_fn, find_fn, kpi_fn, chart_fn, poll_fn, render_fn])

print("[INFO] detected fns:",
      {"gate":gate_fn,"find":find_fn,"kpi":kpi_fn,"chart":chart_fn,"poll":poll_fn,"render":render_fn,"cap":cap})

# We'll inject near top after "window.__vsp_vsp5_rid_reload_v1 = true;" guard (exists per grep line 9)
anchor = "window.__vsp_vsp5_rid_reload_v1 = true;"
pos = s.find(anchor)
if pos == -1:
  # fallback: insert after the marker comment
  pos = s.find("VSP_VSP5_RID_CHANGED_RELOAD_V1")
  if pos == -1: pos = 0

ins_pos = s.find("\n", pos)
if ins_pos == -1: ins_pos = pos

# Build injected code
calls = []
# Prefer a "poll/tick/refresh" single function if it exists
if poll_fn:
  calls.append(f"try {{ await {poll_fn}(); }} catch(e) {{ /* ignore */ }}")
else:
  # Else call gate/find/kpi/chart in a safe order
  if gate_fn:  calls.append(f"try {{ await {gate_fn}(); }} catch(e) {{}}")
  if find_fn:  calls.append(f"try {{ await {find_fn}(); }} catch(e) {{}}")
  if kpi_fn:   calls.append(f"try {{ await {kpi_fn}(); }} catch(e) {{}}")
  if chart_fn: calls.append(f"try {{ await {chart_fn}(); }} catch(e) {{}}")
  if render_fn and not any([gate_fn, find_fn, kpi_fn, chart_fn]):
    calls.append(f"try {{ {render_fn}(); }} catch(e) {{}}")

calls_js = "\n    ".join(calls) if calls else "/* no callable refresh fns detected */"

inject = f"""
/* ===================== {MARK} ===================== */
(()=>{
  if (window.__vsp_p1_vsp5_soft_refresh_apply_v1d) return;
  window.__vsp_p1_vsp5_soft_refresh_apply_v1d = true;

  const __cap = {str(bool(cap)).lower()};
  async function __do_refresh(){{
    {calls_js}
  }}

  // Soft refresh API for core patch
  window.__vsp_soft_refresh_apply = function(newRid, prevRid){{
    try {{
      if (!__cap) return false;                 // let fallback reload happen
      if (!newRid) return false;
      if (newRid === prevRid) return true;

      // Update globals if present
      window.__vsp_rid_prev = prevRid || window.__vsp_rid_prev || null;
      window.__vsp_rid_latest = newRid;

      // Update local state object if present in this bundle
      try {{
        if (typeof state === "object" && state) state.rid = newRid;
      }} catch(e) {{}}

      // Update visible RID labels if exist
      try {{
        const ids = ["rid_txt","rid_val","rid_text","rid_label"];
        for (const id of ids) {{
          const el = document.getElementById(id);
          if (el) el.textContent = newRid;
        }}
      }} catch(e) {{}}

      // Trigger refresh async, but return immediately (core expects boolean)
      Promise.resolve(__do_refresh()).catch(()=>{{}});
      return true;
    }} catch(e) {{
      return false;
    }}
  }};

  // If someone else dispatches vsp:rid_changed, we can also react without reload.
  window.addEventListener("vsp:rid_changed", (ev)=>{{
    try {{
      const d = ev && ev.detail ? ev.detail : null;
      const rid = d && d.rid ? d.rid : (window.__vsp_rid_latest||null);
      const prev = d && d.prev ? d.prev : (window.__vsp_rid_prev||null);
      // Avoid recursion: do not dispatch again here.
      window.__vsp_soft_refresh_apply?.(rid, prev);
    }} catch(e) {{}}
  }}, {{passive:true}});
}})();
/* ===================== /{MARK} ===================== */
"""

s = s[:ins_pos+1] + inject + s[ins_pos+1:]
p.write_text(s, encoding="utf-8")
print("[OK] installed vsp5 soft refresh apply v1d")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check passed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] v1d applied: loop fixed + vsp5 soft refresh apply installed"
