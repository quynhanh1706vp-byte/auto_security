#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_commercial_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_rodd_${TS}"
echo "[BACKUP] ${JS}.bak_rodd_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dashboard_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RULE_OVERRIDES_SYNC_DROPDOWN_V1B"
if MARK in s:
  print("[SKIP] already installed v1b")
  raise SystemExit(0)

addon = textwrap.dedent(f"""
/* ===================== {MARK} ===================== */
(()=> {{
  if (window.__vsp_p1_rule_overrides_sync_dropdown_v1b) return;
  window.__vsp_p1_rule_overrides_sync_dropdown_v1b = true;

  function followOn(){{
    try {{ return (localStorage.getItem("vsp_follow_latest") ?? "on") !== "off"; }}
    catch(e) {{ return true; }}
  }}

  function findRuleOverridesRoot(){{
    // Try to find the section by heading text "Rule Overrides"
    const nodes = Array.from(document.querySelectorAll("h1,h2,h3,div,section"));
    for (const n of nodes) {{
      const t = (n.textContent||"").trim();
      if (t === "Rule Overrides" || t.includes("Rule Overrides")) {{
        // prefer a container near it
        return n.closest("section") || n.closest("div") || document.body;
      }}
    }}
    return document.body;
  }}

  function findRunSelect(){{
    const root = findRuleOverridesRoot();
    // Prefer select that contains RUN_ options
    const sels = Array.from(root.querySelectorAll("select"));
    for (const sel of sels) {{
      const opts = Array.from(sel.options||[]);
      if (opts.some(o => (o.value||"").includes("RUN_") || (o.text||"").includes("RUN_"))) return sel;
    }}
    // Fallback: any select on page that looks like runs
    const all = Array.from(document.querySelectorAll("select"));
    for (const sel of all) {{
      const opts = Array.from(sel.options||[]);
      if (opts.some(o => (o.value||"").includes("RUN_") || (o.text||"").includes("RUN_"))) return sel;
    }}
    return null;
  }}

  function ensureOption(sel, rid){{
    if (!sel) return false;
    const opts = Array.from(sel.options||[]);
    const hit = opts.find(o => (o.value===rid) || (o.text===rid));
    if (hit) {{
      sel.value = hit.value;
      return true;
    }}
    // Not found: prepend a new option (so it can be selected without losing existing list)
    try {{
      const o = document.createElement("option");
      o.value = rid;
      o.textContent = rid;
      sel.insertBefore(o, sel.firstChild);
      sel.value = rid;
      return true;
    }} catch(e) {{
      return false;
    }}
  }}

  function preserveEditor(){{
    // best-effort: keep textarea/codemirror content untouched (we won't write into it anyway)
    const ta = document.querySelector("textarea");
    if (!ta) return null;
    return {{
      el: ta,
      value: ta.value,
      ss: ta.selectionStart,
      se: ta.selectionEnd
    }};
  }}

  function restoreEditor(st){{
    try {{
      if (!st || !st.el) return;
      st.el.value = st.value;
      if (typeof st.ss === "number" && typeof st.se === "number") {{
        st.el.selectionStart = st.ss;
        st.el.selectionEnd = st.se;
      }}
    }} catch(e) {{}}
  }}

  window.addEventListener("vsp:rid_changed", (ev)=> {{
    try {{
      if (!followOn()) return;
      const d = ev && ev.detail ? ev.detail : null;
      const rid = d && d.rid ? d.rid : (window.__vsp_rid_latest||null);
      if (!rid) return;

      const editorState = preserveEditor();

      const sel = findRunSelect();
      ensureOption(sel, rid);

      // Also update any RID labels on this page
      try {{
        const ids = ["rid_txt","rid_val","rid_text","rid_label"];
        for (const id of ids) {{
          const el = document.getElementById(id);
          if (el) el.textContent = rid;
        }}
      }} catch(e) {{}}

      restoreEditor(editorState);
    }} catch(e) {{}}
  }}, {{passive:true}});
}})();
/* ===================== /{MARK} ===================== */
""")

p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended rule_overrides dropdown sync v1b")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check passed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] rule_overrides dropdown sync v1b applied"
