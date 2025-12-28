#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_settings_commercial_v1.js"

mkdir -p static/js
cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true
echo "[BACKUP] ${JS}.bak_${TS}"

cat > "$JS" <<'JS'
/* VSP_P0_SETTINGS_COMMERCIAL_UI_V1 */
(()=> {
  if (window.__vsp_settings_commercial_v1) return;
  window.__vsp_settings_commercial_v1 = true;

  const $ = (sel, root=document)=> root.querySelector(sel);

  function esc(s){
    return String(s??"").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  }

  function nowISO(){
    try{ return new Date().toISOString(); }catch(e){ return ""; }
  }

  function readLocal(){
    try{
      const raw = localStorage.getItem("VSP_SETTINGS_LOCAL_V1");
      if (!raw) return null;
      return JSON.parse(raw);
    }catch(e){ return null; }
  }
  function writeLocal(j){
    localStorage.setItem("VSP_SETTINGS_LOCAL_V1", JSON.stringify(j));
    localStorage.setItem("VSP_SETTINGS_LOCAL_V1_TS", nowISO());
  }

  function validate(j){
    const errs = [];
    if (!j || typeof j !== "object") { errs.push("root must be object"); return errs; }
    // minimal commercial schema (extend later)
    if (!j.tools || typeof j.tools !== "object") errs.push("tools object missing");
    if (j.tools && typeof j.tools === "object"){
      for (const [k,v] of Object.entries(j.tools)){
        if (!v || typeof v !== "object") errs.push(`tools.${k} must be object`);
        else {
          if ("enabled" in v && typeof v.enabled !== "boolean") errs.push(`tools.${k}.enabled must be boolean`);
          if ("timeout_sec" in v && typeof v.timeout_sec !== "number") errs.push(`tools.${k}.timeout_sec must be number`);
        }
      }
    }
    if (j.ui && typeof j.ui !== "object") errs.push("ui must be object if present");
    return errs;
  }

  function download(filename, text){
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([text], {type:"application/json"}));
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    setTimeout(()=>{ URL.revokeObjectURL(a.href); a.remove(); }, 300);
  }

  function ensureShell(){
    const root = $("#vsp_settings_root") || $("#root") || document.body;
    if ($("#vsp_set_box")) return;

    const box = document.createElement("div");
    box.id = "vsp_set_box";
    box.innerHTML = `
      <div class="vsp-set-wrap">
        <div class="vsp-set-head">
          <div class="title">VSP • Settings (Commercial)</div>
          <div class="sub">Export/Import config + validate. (Local-first; server persist can be wired later.)</div>
        </div>

        <div class="vsp-set-row">
          <button id="vsp_set_export" class="btn">Export JSON</button>
          <button id="vsp_set_load" class="btn">Load Local</button>
          <button id="vsp_set_reset" class="btn danger">Reset Local</button>
          <span id="vsp_set_ts" class="muted"></span>
        </div>

        <div class="vsp-set-grid">
          <div class="card">
            <div class="card-h">Import / Edit</div>
            <textarea id="vsp_set_text" class="ta" spellcheck="false" placeholder='{"tools":{...}}'></textarea>
            <div class="vsp-set-row">
              <button id="vsp_set_validate" class="btn">Validate</button>
              <button id="vsp_set_apply" class="btn primary">Apply (Local)</button>
              <span id="vsp_set_msg" class="muted"></span>
            </div>
            <pre id="vsp_set_err" class="pre err" style="display:none"></pre>
          </div>

          <div class="card">
            <div class="card-h">Guidance (CIO/ISO-ready)</div>
            <div class="p">
              <ul>
                <li><b>tools.*.enabled</b>: turn on/off each scanner lane.</li>
                <li><b>tools.*.timeout_sec</b>: enforce degrade-graceful timeouts (KICS/CodeQL).</li>
                <li><b>ui.csp_report_only</b>: keep CSP-RO in early commercial builds.</li>
                <li><b>severity normalization</b>: CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE.</li>
              </ul>
            </div>
            <div class="card-h">Local Snapshot</div>
            <pre id="vsp_set_view" class="pre"></pre>
          </div>
        </div>
      </div>

      <style>
        .vsp-set-wrap{padding:14px 14px 20px}
        .vsp-set-head .title{font-size:20px;font-weight:700;color:#e8eefc}
        .vsp-set-head .sub{opacity:.85;margin-top:4px}
        .vsp-set-row{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:10px 0}
        .btn{padding:8px 12px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:#e8eefc;cursor:pointer}
        .btn.primary{background:rgba(120,180,255,.14);border-color:rgba(120,180,255,.25)}
        .btn.danger{background:rgba(255,120,120,.12);border-color:rgba(255,120,120,.25)}
        .muted{opacity:.8}
        .vsp-set-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
        .card{border:1px solid rgba(255,255,255,.10);border-radius:14px;background:rgba(255,255,255,.03);padding:12px}
        .card-h{font-weight:700;margin-bottom:8px}
        .ta{width:100%;min-height:320px;border-radius:12px;border:1px solid rgba(255,255,255,.14);background:rgba(0,0,0,.22);color:#e8eefc;padding:10px;font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace}
        .pre{white-space:pre-wrap;border-radius:12px;border:1px solid rgba(255,255,255,.10);background:rgba(0,0,0,.18);padding:10px;color:#e8eefc;min-height:140px}
        .pre.err{border-color:rgba(255,120,120,.25);color:#ffb4b4}
        @media (max-width: 980px){ .vsp-set-grid{grid-template-columns:1fr} }
      </style>
    `;
    root.prepend(box);
  }

  function setMsg(s){
    const el = $("#vsp_set_msg");
    if (el) el.textContent = s || "";
  }

  function refreshView(){
    const j = readLocal();
    const ts = localStorage.getItem("VSP_SETTINGS_LOCAL_V1_TS") || "";
    const view = $("#vsp_set_view");
    const tsel = $("#vsp_set_ts");
    if (tsel) tsel.textContent = ts ? `Local TS: ${ts}` : "";
    if (view) view.textContent = j ? JSON.stringify(j, null, 2) : "(no local settings yet)";
  }

  function wire(){
    const ta = $("#vsp_set_text");
    const err = $("#vsp_set_err");

    $("#vsp_set_load")?.addEventListener("click", ()=>{
      const j = readLocal();
      if (ta) ta.value = j ? JSON.stringify(j, null, 2) : "";
      setMsg(j ? "Loaded local settings." : "No local settings.");
      if (err){ err.style.display="none"; err.textContent=""; }
      refreshView();
    });

    $("#vsp_set_reset")?.addEventListener("click", ()=>{
      localStorage.removeItem("VSP_SETTINGS_LOCAL_V1");
      localStorage.removeItem("VSP_SETTINGS_LOCAL_V1_TS");
      if (ta) ta.value = "";
      setMsg("Local settings reset.");
      if (err){ err.style.display="none"; err.textContent=""; }
      refreshView();
    });

    $("#vsp_set_validate")?.addEventListener("click", ()=>{
      try{
        const j = JSON.parse(ta?.value || "null");
        const errs = validate(j);
        if (errs.length){
          if (err){ err.style.display="block"; err.textContent = "INVALID:\n- " + errs.join("\n- "); }
          setMsg("Validation failed.");
        } else {
          if (err){ err.style.display="none"; err.textContent=""; }
          setMsg("Validation OK.");
        }
      } catch(e){
        if (err){ err.style.display="block"; err.textContent = "INVALID JSON:\n" + String(e); }
        setMsg("Validation failed.");
      }
    });

    $("#vsp_set_apply")?.addEventListener("click", ()=>{
      try{
        const j = JSON.parse(ta?.value || "null");
        const errs = validate(j);
        if (errs.length){
          if (err){ err.style.display="block"; err.textContent = "INVALID:\n- " + errs.join("\n- "); }
          setMsg("Apply blocked (invalid).");
          return;
        }
        writeLocal(j);
        if (err){ err.style.display="none"; err.textContent=""; }
        setMsg("Applied locally. (Server persist can be wired next.)");
        refreshView();
      } catch(e){
        if (err){ err.style.display="block"; err.textContent = "INVALID JSON:\n" + String(e); }
        setMsg("Apply failed.");
      }
    });

    $("#vsp_set_export")?.addEventListener("click", ()=>{
      const j = readLocal() || { tools:{}, ui:{} };
      const name = `vsp_settings_local_${(new Date()).toISOString().replace(/[:.]/g,"-")}.json`;
      download(name, JSON.stringify(j, null, 2));
      setMsg("Exported JSON.");
    });
  }

  document.addEventListener("DOMContentLoaded", ()=>{
    ensureShell();
    wire();
    // prefill with local or a safe starter schema
    const ta = $("#vsp_set_text");
    const j = readLocal() || {
      tools: {
        bandit: { enabled:true, timeout_sec: 120 },
        semgrep:{ enabled:true, timeout_sec: 180 },
        gitleaks:{ enabled:true, timeout_sec: 120 },
        kics:{ enabled:true, timeout_sec: 300 },
        trivy:{ enabled:true, timeout_sec: 240 },
        syft:{ enabled:true, timeout_sec: 180 },
        grype:{ enabled:true, timeout_sec: 240 },
        codeql:{ enabled:true, timeout_sec: 900 }
      },
      ui: { csp_report_only: true }
    };
    if (ta && !ta.value) ta.value = JSON.stringify(j, null, 2);
    refreshView();
  });
})();
JS

node --check "$JS" >/dev/null
echo "[OK] node --check passed: $JS"

# ensure templates include loader
TPLS=(templates/vsp_settings_2025.html templates/vsp_settings_v1.html templates/vsp_settings.html)
for t in "${TPLS[@]}"; do
  [ -f "$t" ] || continue
  if ! grep -q "vsp_settings_commercial_v1.js" "$t"; then
    cp -f "$t" "${t}.bak_setui_${TS}"
    python3 - <<PY
from pathlib import Path
import re
p=Path("$t")
s=p.read_text(encoding="utf-8", errors="replace")
ins='<script src="/static/js/vsp_settings_commercial_v1.js?v={{ asset_v|default(\\'\\') }}"></script>'
if ins in s:
  print("[SKIP] already injected:", p)
else:
  if "</body>" in s:
    s=s.replace("</body>", ins+"\\n</body>")
  else:
    s=s+ "\\n" + ins + "\\n"
  p.write_text(s, encoding="utf-8")
  print("[OK] injected:", p)
PY
  fi
done

echo "[DONE] Reload /settings (Ctrl+F5)."
