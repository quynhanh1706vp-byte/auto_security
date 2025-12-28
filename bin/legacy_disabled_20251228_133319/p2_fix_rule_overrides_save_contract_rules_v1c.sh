#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
BUNDLE_JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$BUNDLE_JS" ] || { echo "[ERR] missing $BUNDLE_JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE_JS" "${BUNDLE_JS}.bak_rulesv1save_v1c_${TS}"
echo "[BACKUP] ${BUNDLE_JS}.bak_rulesv1save_v1c_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_RULE_OVERRIDES_SAVE_CONTRACT_RULES_V1C"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r"""
/* VSP_P2_RULE_OVERRIDES_SAVE_CONTRACT_RULES_V1C
   Backend:
     GET  /api/ui/rule_overrides_v2 -> {"ok":true,"schema":"rules_v1","rules":[...],...}
     POST /api/ui/rule_overrides_v2 expects same shape (schema + rules at least)
*/
(function(){
  async function roFix(){
    try{
      if (location.pathname !== "/rule_overrides") return;

      var btnSave = document.getElementById("vsp-ro-save");
      var btnReload = document.getElementById("vsp-ro-reload");
      var ta = document.querySelector("textarea");
      var status = document.getElementById("vsp-ro-status");

      if (!btnSave || !btnReload || !ta) return;

      function setStatus(t, isErr){
        if (!status) return;
        status.textContent = t;
        status.style.opacity = isErr ? "1" : "0.85";
      }

      var schema = "rules_v1";

      async function loadRules(){
        setStatus("Loading...", false);
        var j = await fetch("/api/ui/rule_overrides_v2", {credentials:"same-origin"}).then(function(r){return r.json();});
        schema = (j && j.schema) ? j.schema : "rules_v1";
        var rules = (j && Array.isArray(j.rules)) ? j.rules : [];
        ta.value = JSON.stringify(rules, null, 2);
        setStatus("Loaded (" + schema + "), rules=" + rules.length, false);
      }

      async function saveRules(){
        setStatus("Saving...", false);
        var parsed;
        try{
          parsed = JSON.parse(ta.value || "[]");
        }catch(e){
          setStatus("Textarea is not valid JSON", true);
          return;
        }

        var rules = [];
        if (Array.isArray(parsed)) rules = parsed;
        else if (parsed && Array.isArray(parsed.rules)) rules = parsed.rules;
        else{
          setStatus("JSON must be an array or object with 'rules' array", true);
          return;
        }

        var payload = {schema: (schema || "rules_v1"), rules: rules, notes: "ui"};
        var res = await fetch("/api/ui/rule_overrides_v2", {
          method: "POST",
          credentials: "same-origin",
          headers: {"Content-Type":"application/json"},
          body: JSON.stringify(payload)
        });

        var txt = await res.text();
        if (!res.ok){
          setStatus("Save failed HTTP " + res.status, true);
          try{ console.warn("[VSP][P2] rule_overrides save failed:", res.status, txt.slice(0,300)); }catch(e){}
          return;
        }

        // try parse {ok:true}
        try{
          var j2 = JSON.parse(txt);
          if (j2 && j2.ok === true) setStatus("Saved ✓ rules=" + rules.length, false);
          else setStatus("Saved (server response not ok?)", false);
        }catch(e){
          setStatus("Saved ✓ rules=" + rules.length, false);
        }
      }

      // Override handlers at capture phase (stop older injected handlers)
      btnReload.addEventListener("click", function(ev){
        ev.preventDefault(); ev.stopImmediatePropagation();
        loadRules().catch(function(){ setStatus("Load error", true); });
      }, true);

      btnSave.addEventListener("click", function(ev){
        ev.preventDefault(); ev.stopImmediatePropagation();
        saveRules().catch(function(){ setStatus("Save error", true); });
      }, true);

      if (!window.__VSP_RO_FIX_V1C__){
        window.__VSP_RO_FIX_V1C__ = 1;
        loadRules().catch(function(){});
        try{ console.log("[VSP][P2] rule_overrides save contract fixed (rules_v1) v1c"); }catch(e){}
      }
    }catch(e){
      try{ console.warn("[VSP][P2] roFix v1c error:", e); }catch(_e){}
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", roFix);
  else roFix();
})();
"""

p.write_text(s + "\n\n" + textwrap.dedent(block).strip() + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "== [1] node --check bundle =="
if command -v node >/dev/null 2>&1; then
  node --check "$BUNDLE_JS"
  echo "[OK] node --check passed"
fi

echo
echo "== [2] bump asset_v (if exists) =="
if [ -x "bin/p1_set_asset_v_runtime_ts_v1.sh" ]; then
  bash bin/p1_set_asset_v_runtime_ts_v1.sh || true
fi

echo
echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
fi

echo
echo "== [4] verify API shape =="
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 240; echo

echo
echo "[OK] Open /rule_overrides and click Save; status should show 'Saved ✓ rules=...'"
