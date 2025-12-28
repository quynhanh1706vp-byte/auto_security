#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

DASH_JS="static/js/vsp_dashboard_luxe_v1.js"
BUNDLE_JS="static/js/vsp_bundle_tabs5_v1.js"

[ -f "$DASH_JS" ]   || { echo "[ERR] missing $DASH_JS"; exit 2; }
[ -f "$BUNDLE_JS" ] || { echo "[ERR] missing $BUNDLE_JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$DASH_JS"   "${DASH_JS}.bak_p2_gapfix_${TS}"
cp -f "$BUNDLE_JS" "${BUNDLE_JS}.bak_p2_gapfix_${TS}"
echo "[BACKUP] ${DASH_JS}.bak_p2_gapfix_${TS}"
echo "[BACKUP] ${BUNDLE_JS}.bak_p2_gapfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

dash = Path("static/js/vsp_dashboard_luxe_v1.js")
bund = Path("static/js/vsp_bundle_tabs5_v1.js")

MARK1="VSP_P2_DEGRADED_BANNER_V1"
MARK2="VSP_P2_SETTINGS_TOOL_POLICY_PANEL_V1"
MARK3="VSP_P2_RULE_OVERRIDES_SAVE_BAR_V1"

def append_if_missing(p: Path, marker: str, block: str):
    s = p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[OK] already present:", marker, "in", p)
        return
    s += "\n\n" + block.strip() + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker, "=>", p)

# 1) Dashboard degraded banner (only /vsp5)
block1 = f"""
/* {MARK1} */
(function(){{
  function _vspOnce(key){{
    try {{
      window.__VSP_ONCE__ = window.__VSP_ONCE__ || {{}};
      if (window.__VSP_ONCE__[key]) return false;
      window.__VSP_ONCE__[key] = 1;
      return true;
    }} catch(e){{ return true; }}
  }}

  function _vspStyle(el, css){{
    try{{ for (const k in css) el.style[k]=css[k]; }}catch(e){{}}
  }}

  function _vspInsertBanner(msg, via){{
    if (document.getElementById("vsp-degraded-banner")) return;
    const host = document.getElementById("vsp-dashboard-main") || document.body;
    const b = document.createElement("div");
    b.id = "vsp-degraded-banner";
    b.setAttribute("role","status");
    b.innerHTML = `
      <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;">
        <div style="font-weight:700;letter-spacing:0.2px;">⚠ KPI/Charts Degraded</div>
        <div style="opacity:.9">${{msg}}</div>
        ${{via ? `<div style="opacity:.7;font-size:12px;">via: ${{via}}</div>` : ``}}
      </div>
      <div style="margin-top:6px;opacity:.75;font-size:12px;">
        This is expected when KPI is disabled by policy. UI remains usable; Runs/Data Source/Exports still work.
      </div>
    `;
    _vspStyle(b, {{
      background: "rgba(255, 196, 0, 0.10)",
      border: "1px solid rgba(255, 196, 0, 0.35)",
      padding: "12px 14px",
      borderRadius: "12px",
      margin: "12px auto",
      maxWidth: "1200px",
      color: "#e9edf6",
      fontFamily: "system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial",
    }});
    // Put it above dashboard anchor if possible
    try {{
      if (host && host.parentNode) host.parentNode.insertBefore(b, host);
      else document.body.insertBefore(b, document.body.firstChild);
    }} catch(e){{ document.body.insertBefore(b, document.body.firstChild); }}
  }}

  async function _vspCheckDegraded(){{
    try {{
      if (!location.pathname || location.pathname !== "/vsp5") return;
      const [k, c] = await Promise.all([
        fetch("/api/vsp/dash_kpis", {{credentials:"same-origin"}}).then(r=>r.json()).catch(()=>null),
        fetch("/api/vsp/dash_charts", {{credentials:"same-origin"}}).then(r=>r.json()).catch(()=>null),
      ]);
      const kEmpty = (!k || !k.kpis || Object.keys(k.kpis).length === 0);
      const cEmpty = (!c || !c.charts || Object.keys(c.charts).length === 0);
      if (kEmpty || cEmpty) {{
        const via = (k && k.__via__) || (c && c.__via__) || "";
        const msg = (kEmpty && cEmpty) ? "KPI & charts data not available." : (kEmpty ? "KPI data not available." : "Charts data not available.");
        _vspInsertBanner(msg, via);
        if (_vspOnce("p2_degraded_console_once")) {{
          console.warn("[VSP][P2] Degraded banner shown:", {{kEmpty, cEmpty, via}});
        }}
      }}
    }} catch(e) {{
      if (_vspOnce("p2_degraded_err_once")) console.warn("[VSP][P2] degraded check error:", e);
    }}
  }}

  if (document.readyState === "loading") {{
    document.addEventListener("DOMContentLoaded", _vspCheckDegraded);
  }} else {{
    _vspCheckDegraded();
  }}
}})();
"""

# 2) Settings panel injection (only /settings)
block2 = f"""
/* {MARK2} */
(function(){{
  function _vspEl(tag, attrs, html){{
    const e = document.createElement(tag);
    if (attrs) for (const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]);
    if (html != null) e.innerHTML = html;
    return e;
  }}

  function _vspTryMountSettingsPanel(){{
    try {{
      if (location.pathname !== "/settings") return;
      if (document.getElementById("vsp-settings-commercial-panel")) return;

      const anchor = document.querySelector("#vsp-settings-main") || document.querySelector("main") || document.body;
      const panel = _vspEl("div", {{id:"vsp-settings-commercial-panel"}}, `
        <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
          <div style="font-weight:800;letter-spacing:.2px;">Tool Coverage & Policy (Commercial)</div>
          <div style="opacity:.75;font-size:12px;">8 tools • degrade-graceful • evidence-first</div>
        </div>
        <div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:8px;">
          <span class="vsp-pill">Bandit</span>
          <span class="vsp-pill">Semgrep</span>
          <span class="vsp-pill">Gitleaks</span>
          <span class="vsp-pill">KICS</span>
          <span class="vsp-pill">Trivy</span>
          <span class="vsp-pill">Syft</span>
          <span class="vsp-pill">Grype</span>
          <span class="vsp-pill">CodeQL</span>
        </div>
        <div style="margin-top:10px;opacity:.85;font-size:13px;line-height:1.5;">
          <ul style="margin:0;padding-left:18px;">
            <li><b>Timeout & degrade:</b> long tools (KICS/CodeQL) must timeout and mark <i>degraded</i>, not hang the pipeline.</li>
            <li><b>Severity normalization:</b> CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE.</li>
            <li><b>Artifacts:</b> always keep logs + raw outputs + unified findings + reports for audit/ISO mapping.</li>
            <li><b>Dashboard:</b> if KPI is disabled by policy, UI should show a degraded badge (not blank).</li>
          </ul>
        </div>
      `);

      // lightweight styling (works even without CSS)
      panel.style.cssText = "background:rgba(70,130,255,0.08);border:1px solid rgba(70,130,255,0.22);border-radius:14px;padding:12px 14px;margin:12px auto;max-width:1200px;color:#e9edf6;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,Arial;";
      // add pill style if missing
      if (!document.getElementById("vsp-pill-style")) {{
        const st = _vspEl("style", {{id:"vsp-pill-style"}}, `
          .vsp-pill{{display:inline-block;padding:5px 10px;border-radius:999px;
          background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.14);
          font-size:12px;opacity:.92;}}
        `);
        document.head.appendChild(st);
      }}

      // insert near top
      try {{
        if (anchor && anchor.firstChild) anchor.insertBefore(panel, anchor.firstChild);
        else anchor.appendChild(panel);
      }} catch(e) {{
        document.body.insertBefore(panel, document.body.firstChild);
      }}
      console.log("[VSP][P2] settings commercial panel injected");
    }} catch(e) {{
      console.warn("[VSP][P2] settings panel inject failed:", e);
    }}
  }}

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", _vspTryMountSettingsPanel);
  else _vspTryMountSettingsPanel();
}})();
"""

# 3) Rule overrides Save/Apply bar (only /rule_overrides), with adaptive key
block3 = f"""
/* {MARK3} */
(function(){{
  function _vspEl(tag, attrs, html){{
    const e = document.createElement(tag);
    if (attrs) for (const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]);
    if (html != null) e.innerHTML = html;
    return e;
  }}

  function _pickStringKey(obj){{
    if (!obj || typeof obj !== "object") return null;
    const prefer = ["text","content","raw","rules","overrides","yaml","json","data","value","body"];
    for (const k of prefer) if (typeof obj[k] === "string") return k;
    // fallback: first string field
    for (const k of Object.keys(obj)) if (typeof obj[k] === "string") return k;
    return null;
  }}

  async function _ensureRuleOverridesBar(){{
    try {{
      if (location.pathname !== "/rule_overrides") return;
      if (document.getElementById("vsp-ro-savebar")) return;

      const anchor = document.querySelector("#vsp-rule-overrides-main") || document.querySelector("main") || document.body;

      // find textarea (existing editor) or create one
      let ta = document.querySelector("textarea");
      if (!ta) {{
        ta = _vspEl("textarea", {{id:"vsp-ro-textarea"}}, "");
        ta.style.cssText = "width:100%;min-height:360px;background:rgba(0,0,0,0.25);border:1px solid rgba(255,255,255,0.18);border-radius:12px;padding:10px;color:#e9edf6;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,'Liberation Mono','Courier New',monospace;font-size:12px;line-height:1.45;";
        anchor.appendChild(ta);
      }}

      const bar = _vspEl("div", {{id:"vsp-ro-savebar"}}, `
        <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;">
          <div style="font-weight:800;">Rule Overrides</div>
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
            <button id="vsp-ro-reload" type="button">Reload</button>
            <button id="vsp-ro-save" type="button">Save</button>
            <span id="vsp-ro-status" style="opacity:.8;font-size:12px;"></span>
          </div>
        </div>
      `);
      bar.style.cssText = "background:rgba(0,255,170,0.06);border:1px solid rgba(0,255,170,0.20);border-radius:14px;padding:10px 12px;margin:12px auto;max-width:1200px;color:#e9edf6;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,Arial;";

      // button style
      const st = _vspEl("style", {{id:"vsp-ro-btn-style"}}, `
        #vsp-ro-savebar button{{padding:7px 12px;border-radius:10px;border:1px solid rgba(255,255,255,0.18);
          background:rgba(255,255,255,0.08);color:#e9edf6;cursor:pointer;}}
        #vsp-ro-savebar button:hover{{background:rgba(255,255,255,0.12);}}
      `);
      document.head.appendChild(st);

      try {{
        if (anchor && anchor.firstChild) anchor.insertBefore(bar, anchor.firstChild);
        else anchor.appendChild(bar);
      }} catch(e) {{
        document.body.insertBefore(bar, document.body.firstChild);
      }}

      const status = document.getElementById("vsp-ro-status");
      const setStatus = (t, isErr=false)=>{{ if(status) status.textContent = t; if(status) status.style.opacity=isErr? "1":"0.85"; }};

      let apiKey = null;

      async function load() {{
        setStatus("Loading...");
        const j = await fetch("/api/ui/rule_overrides_v2", {{credentials:"same-origin"}}).then(r=>r.json());
        apiKey = _pickStringKey(j);
        if (apiKey && typeof j[apiKey] === "string") {{
          ta.value = j[apiKey];
          setStatus("Loaded ("+apiKey+")");
        }} else {{
          // if server returns structured JSON, store pretty text
          ta.value = JSON.stringify(j, null, 2);
          setStatus("Loaded (json)");
        }}
      }}

      async function save() {{
        setStatus("Saving...");
        let payload = null;
        if (apiKey) {{
          payload = {{[apiKey]: ta.value}};
        }} else {{
          // fallback – try common key
          payload = {{text: ta.value}};
        }}
        const res = await fetch("/api/ui/rule_overrides_v2", {{
          method: "POST",
          credentials: "same-origin",
          headers: {{"Content-Type":"application/json"}},
          body: JSON.stringify(payload),
        }});
        const txt = await res.text();
        if (res.ok) {{
          setStatus("Saved ✓");
        }} else {{
          setStatus("Save failed: HTTP "+res.status, true);
          console.warn("[VSP][P2] rule_overrides save failed:", res.status, txt.slice(0,300));
        }}
      }}

      document.getElementById("vsp-ro-reload")?.addEventListener("click", ()=>load().catch(e=>setStatus("Load error", true)));
      document.getElementById("vsp-ro-save")?.addEventListener("click", ()=>save().catch(e=>setStatus("Save error", true)));

      await load();
      console.log("[VSP][P2] rule_overrides save bar injected");
    }} catch(e) {{
      console.warn("[VSP][P2] rule_overrides inject failed:", e);
    }}
  }}

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", _ensureRuleOverridesBar);
  else _ensureRuleOverridesBar();
}})();
"""

append_if_missing(dash, MARK1, block1)
append_if_missing(bund, MARK2, block2)
append_if_missing(bund, MARK3, block3)

# quick syntax check (best-effort)
try:
    py_compile.compile(str(dash), doraise=True)
    py_compile.compile(str(bund), doraise=True)
except Exception as e:
    raise SystemExit("[ERR] python compile check failed: "+repr(e))

print("[OK] JS patched")
PY

# optional: if you have a script that bumps asset_v, run it (helps cache bust)
if [ -x "bin/p1_set_asset_v_runtime_ts_v1.sh" ]; then
  bash bin/p1_set_asset_v_runtime_ts_v1.sh || true
fi

# restart service to ensure templates re-render asset_v (if used)
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
fi

echo
echo "== QUICK VERIFY =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -s -o /dev/null -w "GET /vsp5 => %{http_code}\n" "$BASE/vsp5" || true
curl -s -o /dev/null -w "GET /settings => %{http_code}\n" "$BASE/settings" || true
curl -s -o /dev/null -w "GET /rule_overrides => %{http_code}\n" "$BASE/rule_overrides" || true

echo
echo "== CHECK: degraded banner trigger (kpis empty) =="
curl -fsS "$BASE/api/vsp/dash_kpis" | head -c 220; echo
curl -fsS "$BASE/api/vsp/dash_charts" | head -c 220; echo

echo
echo "[OK] Done. Open /vsp5, /settings, /rule_overrides to confirm UI."
