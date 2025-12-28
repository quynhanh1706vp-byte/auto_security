#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BUNDLE_JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$BUNDLE_JS" ] || { echo "[ERR] missing $BUNDLE_JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE_JS" "${BUNDLE_JS}.bak_rulesv1save_${TS}"
echo "[BACKUP] ${BUNDLE_JS}.bak_rulesv1save_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P2_RULE_OVERRIDES_SAVE_CONTRACT_RULES_V1B"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = f"""
/* {MARK}
   Fix Save/Reload behavior to match backend contract:
   GET /api/ui/rule_overrides_v2 => {{ok, schema:'rules_v1', rules:[...], notes}}
   POST /api/ui/rule_overrides_v2 expects same shape (at least schema + rules)
*/
(function(){{
  async function _roFix(){{
    try {{
      if (location.pathname !== "/rule_overrides") return;

      const btnSave = document.getElementById("vsp-ro-save");
      const btnReload = document.getElementById("vsp-ro-reload");
      const ta = document.querySelector("textarea");
      const status = document.getElementById("vsp-ro-status");

      if (!btnSave || !btnReload || !ta) return;

      let schema = "rules_v1";

      const setStatus = (t, isErr=false)=>{{
        if (!status) return;
        status.textContent = t;
        status.style.opacity = isErr ? "1" : "0.85";
      }};

      async function loadRules(){{
        setStatus("Loading...");
        const j = await fetch("/api/ui/rule_overrides_v2", {{credentials:"same-origin"}}).then(r=>r.json());
        schema = (j && j.schema) ? j.schema : "rules_v1";
        const rules = (j && Array.isArray(j.rules)) ? j.rules : [];
        ta.value = JSON.stringify(rules, null, 2);
        setStatus("Loaded (" + schema + "), rules=" + rules.length);
      }}

      async function saveRules(){{
        setStatus("Saving...");
        let parsed = null;
        try {{
          parsed = JSON.parse(ta.value || "[]");
        }} catch(e) {{
          setStatus("Textarea is not valid JSON", true);
          return;
        }}

        let rules = [];
        if (Array.isArray(parsed)) rules = parsed;
        else if (parsed && Array.isArray(parsed.rules)) rules = parsed.rules;
        else {{
          setStatus("JSON must be an array or an object with 'rules' array", true);
          return;
        }}

        const payload = {{ schema: schema || "rules_v1", rules, notes: "ui" }};
        const res = await fetch("/api/ui/rule_overrides_v2", {{
          method: "POST",
          credentials: "same-origin",
          headers: {{ "Content-Type":"application/json" }},
          body: JSON.stringify(payload),
        }});
        const txt = await res.text();
        if (!res.ok) {{
          setStatus("Save failed HTTP " + res.status, true);
          console.warn("[VSP][P2] rule_overrides save failed:", res.status, txt.slice(0,300));
          return;
        }}
        // best-effort parse ok flag
        try {{
          const j2 = JSON.parse(txt);
          if (j2 && j2.ok === true) setStatus("Saved ✓ rules=" + rules.length);
          else setStatus("Saved (check server response)", false);
        }} catch(e) {{
          setStatus("Saved ✓", false);
        }}
      }}

      // CAPTURE listeners: stop old handler
      btnReload.addEventListener("click", (e)=>{{ e.preventDefault(); e.stopImmediatePropagation(); loadRules().catch(err=>setStatus("Load error", true)); }}, true);
      btnSave.addEventListener("click", (e)=>{{ e.preventDefault(); e.stopImmediatePropagation(); saveRules().catch(err=>setStatus("Save error", true)); }}, true);

      // auto-load once
      if (!window.__VSP_RO_FIX_ONCE__) {{
        window.__VSP_RO_FIX_ONCE__ = 1;
        loadRules().catch(()=>{});
        console.log("[VSP][P2] rule_overrides save contract fixed (rules_v1)");
      }}
    }} catch(e) {{
      console.warn("[VSP][P2] ro fix error:", e);
    }}
  }}

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", _roFix);
  else _roFix();
}})();
"""
p.write_text(s + "\n\n" + textwrap.dedent(block).strip() + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

# bump cache if available
if [ -x "bin/p1_set_asset_v_runtime_ts_v1.sh" ]; then
  bash bin/p1_set_asset_v_runtime_ts_v1.sh || true
fi

# restart
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
fi

echo
echo "== VERIFY API shape =="
curl -fsS http://127.0.0.1:8910/api/ui/rule_overrides_v2 | head -c 220; echo
echo "[OK] Open /rule_overrides and click Save; status should show Saved ✓"
