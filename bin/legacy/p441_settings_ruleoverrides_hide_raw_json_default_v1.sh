#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need sudo; need date

mkdir -p static/js

# 1) Settings commercial summary JS
cat > static/js/vsp_settings_commercial_summary_v1.js <<'JS'
;(()=> {
  const MARK="VSP_P441_SETTINGS_SUMMARY_V1";
  if (window.__VSP_P441_SETTINGS_SUMMARY__) return;
  window.__VSP_P441_SETTINGS_SUMMARY__ = 1;

  function el(tag, attrs={}, kids=[]){
    const e=document.createElement(tag);
    for(const [k,v] of Object.entries(attrs||{})){
      if(k==="class") e.className=v;
      else if(k==="style") e.setAttribute("style", v);
      else if(k.startsWith("on") && typeof v==="function") e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, String(v));
    }
    for(const k of (Array.isArray(kids)?kids:[kids])) if(k!=null) e.append(k.nodeType?k:document.createTextNode(String(k)));
    return e;
  }

  function findJsonTextarea(){
    // ưu tiên textarea lớn nhất
    const t=[...document.querySelectorAll("textarea")];
    if(!t.length) return null;
    t.sort((a,b)=> (b.value||"").length - (a.value||"").length);
    return t[0];
  }

  function safeParse(s){
    try{ return JSON.parse(s); } catch(e){ return null; }
  }

  function kvTable(rows){
    const table=el("table",{class:"vsp_tbl vsp_tbl_kv",style:"width:100%;border-collapse:collapse"});
    const tb=el("tbody");
    for(const [k,v] of rows){
      tb.append(el("tr",{},[
        el("td",{style:"padding:6px 10px;opacity:.9;white-space:nowrap;width:240px"},k),
        el("td",{style:"padding:6px 10px;opacity:.95"},v)
      ]));
    }
    table.append(tb);
    return table;
  }

  function summarizeSettings(j){
    const rows=[];
    const tools=(j && j.tools) ? j.tools : (j && j.config && j.config.tools) ? j.config.tools : null;
    if (tools && typeof tools === "object"){
      const names=Object.keys(tools);
      const enabled=names.filter(n => (tools[n] && tools[n].enabled===True) );
      // Python JSON uses true/false; in JS it’s true/false
      const enabled2=names.filter(n => (tools[n] && tools[n].enabled===true));
      rows.push(["Tools", `${enabled2.length}/${names.length} enabled`]);
      const timeouts=names.map(n=>{
        const t=tools[n] && (tools[n].timeout_sec ?? tools[n].timeout ?? null);
        return t!=null ? `${n}:${t}` : null;
      }).filter(Boolean).join(", ");
      if(timeouts) rows.push(["Timeouts", timeouts]);
    }
    // common keys fallbacks
    for (const k of ["mode","profile","degrade","degraded_ok","policy","severity_norm","runner","export","iso27001"]){
      if (j && j[k]!=null){
        const v=typeof j[k]==="object" ? JSON.stringify(j[k]).slice(0,160) : String(j[k]);
        rows.push([k, v]);
      }
    }
    if(!rows.length) rows.push(["Settings", "Loaded (no summary keys matched)"]);
    return rows;
  }

  function install(){
    const ta=findJsonTextarea();
    if(!ta) return;

    // Avoid double-install
    if (ta.dataset && ta.dataset.vspP441==="1") return;
    if (ta.dataset) ta.dataset.vspP441="1";

    const raw=ta.value || ta.textContent || "";
    const j=safeParse(raw);

    const panel=el("div",{class:"vsp_card",style:"margin:10px 0;padding:12px;border-radius:12px;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06)"});
    const title=el("div",{style:"display:flex;align-items:center;justify-content:space-between;gap:10px"},[
      el("div",{style:"font-weight:700;letter-spacing:.2px"}, "Settings (Commercial)"),
      el("div",{style:"display:flex;gap:8px;align-items:center"},[])
    ]);

    const btn=el("button",{type:"button",class:"btn",style:"padding:6px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.04);color:#e8eefc;cursor:pointer"}, "Advanced JSON");
    btn.addEventListener("click", ()=>{
      const shown = (rawWrap.style.display !== "none");
      rawWrap.style.display = shown ? "none" : "block";
      btn.textContent = shown ? "Advanced JSON" : "Hide Advanced";
    });
    title.lastChild.append(btn);

    const body=el("div",{style:"margin-top:10px"},[
      j ? kvTable(summarizeSettings(j)) : el("div",{style:"opacity:.8"}, "Cannot parse JSON in editor (still preserved in Advanced).")
    ]);

    // wrap raw textarea in collapsible
    const rawWrap=el("div",{style:"display:none;margin-top:10px"});
    const rawHint=el("div",{style:"opacity:.7;margin:6px 0 8px 0;font-size:12px"}, "Advanced (raw JSON) — kept for rollback/audit.");
    rawWrap.append(rawHint);
    rawWrap.append(ta);

    // insert panel before textarea original position
    const anchor = ta.parentElement;
    (anchor && anchor.parentElement ? anchor.parentElement : document.body).insertBefore(panel, anchor || null);

    panel.append(title);
    panel.append(body);
    panel.append(rawWrap);
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", install);
  else install();
})();
JS

# 2) Rule Overrides commercial summary JS
cat > static/js/vsp_rule_overrides_commercial_summary_v1.js <<'JS'
;(()=> {
  const MARK="VSP_P441_RULE_OVERRIDES_SUMMARY_V1";
  if (window.__VSP_P441_RULE_OVERRIDES__) return;
  window.__VSP_P441_RULE_OVERRIDES__ = 1;

  function el(tag, attrs={}, kids=[]){
    const e=document.createElement(tag);
    for(const [k,v] of Object.entries(attrs||{})){
      if(k==="class") e.className=v;
      else if(k==="style") e.setAttribute("style", v);
      else if(k.startsWith("on") && typeof v==="function") e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, String(v));
    }
    for(const k of (Array.isArray(kids)?kids:[kids])) if(k!=null) e.append(k.nodeType?k:document.createTextNode(String(k)));
    return e;
  }
  function findJsonTextarea(){
    const t=[...document.querySelectorAll("textarea")];
    if(!t.length) return null;
    t.sort((a,b)=> (b.value||"").length - (a.value||"").length);
    return t[0];
  }
  function safeParse(s){ try{ return JSON.parse(s); } catch(e){ return null; } }

  function tableFromRules(rules){
    const wrap=el("div",{style:"overflow:auto;max-height:420px;border:1px solid rgba(255,255,255,.06);border-radius:12px"});
    const table=el("table",{style:"width:100%;border-collapse:collapse;font-size:13px"});
    const th=el("thead",{},el("tr",{},[
      el("th",{style:"text-align:left;padding:8px 10px;opacity:.8;position:sticky;top:0;background:rgba(10,16,28,.95)"}, "Rule"),
      el("th",{style:"text-align:left;padding:8px 10px;opacity:.8;position:sticky;top:0;background:rgba(10,16,28,.95)"}, "Tool"),
      el("th",{style:"text-align:left;padding:8px 10px;opacity:.8;position:sticky;top:0;background:rgba(10,16,28,.95)"}, "Action"),
      el("th",{style:"text-align:left;padding:8px 10px;opacity:.8;position:sticky;top:0;background:rgba(10,16,28,.95)"}, "Reason"),
    ]));
    const tb=el("tbody");
    for(const r of rules){
      tb.append(el("tr",{},[
        el("td",{style:"padding:8px 10px;opacity:.95;white-space:nowrap"}, r.id||r.rule||"(unknown)"),
        el("td",{style:"padding:8px 10px;opacity:.9"}, r.tool||r.source||"-"),
        el("td",{style:"padding:8px 10px;opacity:.9"}, r.action||r.override||r.severity||"-"),
        el("td",{style:"padding:8px 10px;opacity:.8;max-width:520px"}, (r.reason||r.note||"").slice(0,160)),
      ]));
    }
    table.append(th); table.append(tb);
    wrap.append(table);
    return wrap;
  }

  function install(){
    const ta=findJsonTextarea();
    if(!ta) return;
    if (ta.dataset && ta.dataset.vspP441==="1") return;
    if (ta.dataset) ta.dataset.vspP441="1";

    const raw=ta.value || ta.textContent || "";
    const j=safeParse(raw);

    let rules=[];
    if (j){
      if (Array.isArray(j.rules)) rules=j.rules;
      else if (j.rules && typeof j.rules==="object") rules=Object.values(j.rules);
      else if (j.overrides && Array.isArray(j.overrides)) rules=j.overrides;
    }

    const panel=el("div",{class:"vsp_card",style:"margin:10px 0;padding:12px;border-radius:12px;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06)"});
    const top=el("div",{style:"display:flex;align-items:center;justify-content:space-between;gap:10px"},[
      el("div",{style:"font-weight:700;letter-spacing:.2px"}, `Rule Overrides (Commercial) — ${rules.length} rules`),
      el("div",{style:"display:flex;gap:8px;align-items:center"},[])
    ]);

    const btn=el("button",{type:"button",style:"padding:6px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.04);color:#e8eefc;cursor:pointer"}, "Advanced JSON");
    btn.addEventListener("click", ()=>{
      const shown = (rawWrap.style.display !== "none");
      rawWrap.style.display = shown ? "none" : "block";
      btn.textContent = shown ? "Advanced JSON" : "Hide Advanced";
    });
    top.lastChild.append(btn);

    const body = rules.length ? tableFromRules(rules) : el("div",{style:"opacity:.8"}, "No rules parsed (still preserved in Advanced).");

    const rawWrap=el("div",{style:"display:none;margin-top:10px"});
    rawWrap.append(el("div",{style:"opacity:.7;margin:6px 0 8px 0;font-size:12px"}, "Advanced (raw JSON) — kept for rollback/audit."));
    rawWrap.append(ta);

    const anchor = ta.parentElement;
    (anchor && anchor.parentElement ? anchor.parentElement : document.body).insertBefore(panel, anchor || null);

    panel.append(top);
    panel.append(el("div",{style:"margin-top:10px"},body));
    panel.append(rawWrap);
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", install);
  else install();
})();
JS

# 3) Patch templates to load these JS on settings + rule_overrides pages
python3 - <<'PY'
from pathlib import Path
import datetime, re

ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
injects=[
  '/static/js/vsp_settings_commercial_summary_v1.js',
  '/static/js/vsp_rule_overrides_commercial_summary_v1.js',
]
targets=[]
for p in Path("templates").glob("**/*.html"):
  s=p.read_text(encoding="utf-8", errors="replace")
  # Heuristic: template mentions settings/rule_overrides routes or titles
  if any(x in s.lower() for x in ["settings", "rule_overrides", "rule overrides", "/c/settings", "/c/rule_overrides"]):
    targets.append(p)

patched=0
for p in targets:
  s=p.read_text(encoding="utf-8", errors="replace")
  need_any = False
  for js in injects:
    if js not in s:
      need_any = True
  if not need_any:
    continue
  bak=p.with_suffix(p.suffix+f".bak_p441_{ts}")
  bak.write_text(s, encoding="utf-8")

  # inject before </body> if possible, else </head>
  block="\n".join([f'  <script defer src="{js}"></script>' for js in injects if js not in s]) + "\n"
  if "</body>" in s:
    s2=s.replace("</body>", block+"</body>", 1)
  elif "</head>" in s:
    s2=s.replace("</head>", block+"</head>", 1)
  else:
    s2=s + "\n" + block
  p.write_text(s2, encoding="utf-8")
  patched += 1

print("patched_templates=", patched, "targets=", len(targets))
PY

# quick syntax check
node -c static/js/vsp_settings_commercial_summary_v1.js >/dev/null
node -c static/js/vsp_rule_overrides_commercial_summary_v1.js >/dev/null

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"
