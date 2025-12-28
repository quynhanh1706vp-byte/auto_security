#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_tabs3v2_${TS}"
echo "[BACKUP] ${W}.bak_tabs3v2_${TS}"

mkdir -p static/js

python3 - <<'PY'
from pathlib import Path
import re, json, time

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")

# -------------------------
# 1) Blueprint APIs (v2, avoid conflicts)
# -------------------------
bp = ROOT/"vsp_tabs3_ui_bp_v2.py"
if not bp.exists():
    bp.write_text(r'''# -*- coding: utf-8 -*-
from __future__ import annotations
from flask import Blueprint, jsonify, request
from pathlib import Path
import os, json, time

vsp_tabs3_ui_bp_v2 = Blueprint("vsp_tabs3_ui_bp_v2", __name__)

def _now(): return int(time.time())

def _ui_root() -> Path:
    return Path(os.environ.get("VSP_UI_ROOT", str(Path.cwd()))).resolve()

def _out_candidates():
    env = os.environ.get("SECURITY_BUNDLE_OUT") or os.environ.get("VSP_OUT_DIR")
    if env: return [Path(env)]
    return [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]

def _latest_run_dir():
    roots = [p for p in _out_candidates() if p.exists()]
    run_dirs = []
    for r in roots:
        for d in r.glob("RUN_*"):
            if d.is_dir(): run_dirs.append(d)
        for d in r.glob("**/RUN_*"):
            if d.is_dir(): run_dirs.append(d)

    run_dirs = sorted(set(run_dirs), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    rels = [Path("reports/findings_unified.json"), Path("findings_unified.json"), Path("findings/findings_unified.json")]
    for d in run_dirs[:250]:
        for rel in rels:
            if (d/rel).exists():
                return d, (d/rel)
    return (run_dirs[0], None) if run_dirs else (None, None)

def _norm_sev(x):
    x = (str(x or "").strip().upper())
    if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"): return x
    return {"ERROR":"HIGH","WARN":"MEDIUM","WARNING":"MEDIUM","UNKNOWN":"INFO","NONE":"INFO"}.get(x, "INFO")

def _row(d):
    sev = _norm_sev(d.get("severity") or d.get("sev") or d.get("level"))
    return {
        "severity": sev,
        "tool": str(d.get("tool") or d.get("scanner") or d.get("engine") or "unknown"),
        "rule_id": str(d.get("rule_id") or d.get("rule") or d.get("check_id") or d.get("id") or ""),
        "message": str(d.get("message") or d.get("msg") or d.get("title") or d.get("description") or "")[:2000],
        "file": str(d.get("file") or d.get("path") or d.get("filename") or ""),
        "line": d.get("line") or d.get("start_line") or d.get("line_number") or "",
        "cwe": d.get("cwe") or d.get("cwe_id") or "",
        "confidence": d.get("confidence") or d.get("precision") or "",
    }

def _counts(items):
    c = {k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}
    for it in items: c[_norm_sev(it.get("severity"))] += 1
    c["TOTAL"] = sum(c.values())
    return c

@vsp_tabs3_ui_bp_v2.get("/api/vsp/ui_findings_v2")
def ui_findings_v2():
    limit = int(request.args.get("limit","20") or 20)
    offset = int(request.args.get("offset","0") or 0)
    q = (request.args.get("q") or "").strip().lower()
    sev = (request.args.get("severity") or "").strip().upper()
    tool = (request.args.get("tool") or "").strip().lower()

    run_dir, fp = _latest_run_dir()
    if not run_dir or not fp or not fp.exists():
        return jsonify({"ok": True, "items": [], "total": 0, "counts": _counts([]), "run_dir": None, "ts": _now()})

    try:
        data = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        data = []

    if isinstance(data, dict):
        for k in ("items","findings","results","rows"):
            if isinstance(data.get(k), list):
                data = data[k]; break
    if not isinstance(data, list): data = []

    rows = [_row(x) for x in data if isinstance(x, dict)]

    def ok(it):
        if sev and _norm_sev(it.get("severity")) != sev: return False
        if tool and (it.get("tool","").lower() != tool): return False
        if q:
            hay = " ".join([str(it.get(k,"")) for k in ("tool","rule_id","message","file","cwe")]).lower()
            if q not in hay: return False
        return True

    rows = [r for r in rows if ok(r)]
    total = len(rows)
    counts = _counts(rows)
    rank = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3,"INFO":4,"TRACE":5}
    rows.sort(key=lambda r: (rank.get(_norm_sev(r.get("severity")), 9), r.get("tool",""), r.get("rule_id","")))
    items = rows[offset:offset+limit]
    return jsonify({"ok": True, "items": items, "total": total, "counts": counts, "run_dir": str(run_dir), "ts": _now(),
                    "limit": limit, "offset": offset, "q": q, "severity": sev, "tool": tool})

def _state_dir(name):
    d = _ui_root()/"out_ci"/name
    d.mkdir(parents=True, exist_ok=True)
    return d

@vsp_tabs3_ui_bp_v2.get("/api/vsp/ui_settings_v2")
def ui_settings_get_v2():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    try:
        settings = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {}
    except Exception:
        settings = {}
    return jsonify({"ok": True, "settings": settings, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v2.post("/api/vsp/ui_settings_v2")
def ui_settings_set_v2():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    body = request.get_json(silent=True) or {}
    settings = body.get("settings", body)
    if not isinstance(settings, dict):
        return jsonify({"ok": False, "err": "settings must be object"}), 400
    p.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v2.get("/api/vsp/ui_rule_overrides_v2")
def ui_rules_get_v2():
    p = _state_dir("rule_overrides_v2")/"rules.json"
    try:
        data = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {"rules":[]}
    except Exception:
        data = {"rules":[]}
    if isinstance(data, list): data = {"rules": data}
    if not isinstance(data, dict): data = {"rules":[]}
    if not isinstance(data.get("rules"), list): data["rules"] = []
    return jsonify({"ok": True, "data": data, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v2.post("/api/vsp/ui_rule_overrides_v2")
def ui_rules_set_v2():
    p = _state_dir("rule_overrides_v2")/"rules.json"
    body = request.get_json(silent=True) or {}
    data = body.get("data", body)
    if isinstance(data, list): data = {"rules": data}
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        return jsonify({"ok": False, "err": "expect {rules:[...]}" }), 400
    out = {"rules": [r for r in data["rules"] if isinstance(r, dict)], "updated_ts": _now()}
    p.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "rules_n": len(out["rules"]), "ts": _now()})
''', encoding="utf-8")
    print("[OK] created", bp)
else:
    print("[OK] exists", bp)

# -------------------------
# 2) Patch gateway: register blueprint + fix Content-Length:0 for HTML
# -------------------------
w = ROOT/"wsgi_vsp_ui_gateway.py"
s = w.read_text(encoding="utf-8", errors="replace")

# (a) after_request Content-Length fix
fix_marker = "VSP_P1_FIX_CONTENT_LENGTH_ZERO_V1"
if fix_marker not in s:
    insert = r'''
# --- VSP_P1_FIX_CONTENT_LENGTH_ZERO_V1 ---
try:
    @app.after_request
    def _vsp_fix_cl_zero(resp):
        try:
            ct = (resp.content_type or "")
            if ct.startswith("text/html"):
                cl = resp.headers.get("Content-Length")
                if cl == "0":
                    b = resp.get_data()
                    if b:
                        resp.headers["Content-Length"] = str(len(b))
        except Exception:
            pass
        return resp
except Exception as _e:
    print("[VSP_FIX_CL0] disabled:", _e)
# --- /VSP_P1_FIX_CONTENT_LENGTH_ZERO_V1 ---
'''
    # inject after app creation if possible
    m = re.search(r'^\s*app\s*=\s*Flask\([^\n]*\)\s*$', s, flags=re.M)
    if m:
        pos = m.end()
        s = s[:pos] + "\n" + insert + s[pos:]
        print("[OK] injected after_request fix after app=Flask")
    else:
        s += "\n" + insert
        print("[WARN] appended after_request fix at EOF")
else:
    print("[OK] content-length fix already present")

# (b) register blueprint
bp_marker = "VSP_P1_TABS3_UI_BP_REGISTER_V2"
if bp_marker not in s:
    reg = r'''
# --- VSP_P1_TABS3_UI_BP_REGISTER_V2 ---
try:
    from vsp_tabs3_ui_bp_v2 import vsp_tabs3_ui_bp_v2 as _vsp_tabs3_ui_bp_v2
    if "app" in globals() and hasattr(globals()["app"], "register_blueprint"):
        globals()["app"].register_blueprint(_vsp_tabs3_ui_bp_v2)
        print("[VSP_TABS3_V2] registered blueprint: vsp_tabs3_ui_bp_v2")
except Exception as _e:
    print("[VSP_TABS3_V2] blueprint disabled:", _e)
# --- /VSP_P1_TABS3_UI_BP_REGISTER_V2 ---
'''
    s += "\n" + reg
    print("[OK] appended blueprint register")
else:
    print("[OK] blueprint register already present")

w.write_text(s, encoding="utf-8")

# -------------------------
# 3) JS per-tab (keeps current UI; only renders inside #vsp_tab_root)
# -------------------------
def write_js(path: Path, body: str):
    if path.exists():
        old = path.read_text(encoding="utf-8", errors="replace")
        if "VSP_TABS3_V2" in old:
            print("[OK] js exists", path); return
    path.write_text(body, encoding="utf-8")
    print("[OK] wrote", path)

common = r'''
/* VSP_TABS3_V2 common */
(() => {
  const $ = (s, r=document) => r.querySelector(s);
  const esc = (x)=> (x==null?'':String(x)).replace(/[&<>"']/g, c=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  async function api(url, opt){
    const r = await fetch(url, opt);
    const t = await r.text();
    let j; try{ j=JSON.parse(t); }catch(e){ j={ok:false, err:"non-json", raw:t.slice(0,800)}; }
    if(!r.ok) throw Object.assign(new Error("HTTP "+r.status), {status:r.status, body:j});
    return j;
  }
  function ensure(){
    if(document.getElementById("vsp_tabs3_v2_style")) return;
    const st=document.createElement("style");
    st.id="vsp_tabs3_v2_style";
    st.textContent=`
      .vsp-card{background:#0f1b2d;border:1px solid rgba(148,163,184,.18);border-radius:14px;padding:14px}
      .vsp-row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
      .vsp-btn{background:#111c30;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:7px 10px;cursor:pointer}
      .vsp-btn:hover{border-color:rgba(148,163,184,.45)}
      .vsp-in{background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:7px 10px;outline:none}
      .vsp-muted{color:#94a3b8}
      .vsp-badge{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(148,163,184,.22);font-size:12px}
      table.vsp-t{width:100%;border-collapse:separate;border-spacing:0 8px}
      table.vsp-t th{font-weight:600;text-align:left;color:#cbd5e1;font-size:12px;padding:0 10px}
      table.vsp-t td{background:#0b1324;border-top:1px solid rgba(148,163,184,.18);border-bottom:1px solid rgba(148,163,184,.18);padding:10px;font-size:13px;vertical-align:top}
      table.vsp-t tr td:first-child{border-left:1px solid rgba(148,163,184,.18);border-top-left-radius:12px;border-bottom-left-radius:12px}
      table.vsp-t tr td:last-child{border-right:1px solid rgba(148,163,184,.18);border-top-right-radius:12px;border-bottom-right-radius:12px}
      .vsp-code{width:100%;min-height:320px;resize:vertical;font-family:ui-monospace,Menlo,Monaco,Consolas,monospace;background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:12px;padding:12px}
      .vsp-ok{color:#86efac}.vsp-err{color:#fca5a5}
    `;
    document.head.appendChild(st);
  }
  window.__vsp_tabs3_v2 = { $, esc, api, ensure };
})();
'''

write_js(ROOT/"static/js/vsp_tabs3_common_v2.js", common)

ds = r'''
/* VSP_TABS3_V2 Data Source */
(() => {
  if(window.__vsp_ds_v2) return; window.__vsp_ds_v2=true;
  const { $, esc, api, ensure } = window.__vsp_tabs3_v2 || {};
  if(!ensure) return;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Data Source</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Findings table (latest run) · filter/search/pagination</div>
        </div>
        <div class="vsp-row">
          <button class="vsp-btn" id="ds_refresh">Refresh</button>
        </div>
      </div>

      <div class="vsp-card" style="margin-bottom:10px">
        <div class="vsp-row">
          <input class="vsp-in" id="ds_q" placeholder="search (tool/rule/message/file/cwe)..." style="flex:1;min-width:240px">
          <select class="vsp-in" id="ds_sev">
            <option value="">Overall: ALL</option>
            <option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option><option>INFO</option><option>TRACE</option>
          </select>
          <input class="vsp-in" id="ds_tool" placeholder="tool (exact)" style="min-width:160px">
          <select class="vsp-in" id="ds_limit">
            <option value="10">10/page</option>
            <option value="20" selected>20/page</option>
            <option value="50">50/page</option>
          </select>
        </div>
        <div class="vsp-muted" id="ds_meta" style="margin-top:8px;font-size:12px"></div>
      </div>

      <div class="vsp-card">
        <table class="vsp-t">
          <thead><tr><th>Severity</th><th>Tool</th><th>Rule</th><th>File</th><th>Line</th><th>Message</th></tr></thead>
          <tbody id="ds_tb"></tbody>
        </table>
        <div class="vsp-row" style="justify-content:flex-end;margin-top:8px">
          <button class="vsp-btn" id="ds_prev">Prev</button>
          <div class="vsp-muted" id="ds_page" style="min-width:110px;text-align:center">1/1</div>
          <button class="vsp-btn" id="ds_next">Next</button>
        </div>
      </div>
    `;

    const st = { offset:0, limit:20, total:0 };

    const q=$("#ds_q"), sev=$("#ds_sev"), tool=$("#ds_tool"), lim=$("#ds_limit");
    const tb=$("#ds_tb"), meta=$("#ds_meta"), page=$("#ds_page");

    function debounce(fn, ms=250){ let t=null; return ()=>{ clearTimeout(t); t=setTimeout(fn,ms); }; }

    async function load(){
      st.limit = parseInt(lim.value||"20",10)||20;
      const url = `/api/vsp/ui_findings_v2?limit=${encodeURIComponent(st.limit)}&offset=${encodeURIComponent(st.offset)}&q=${encodeURIComponent((q.value||"").trim())}&severity=${encodeURIComponent((sev.value||"").trim())}&tool=${encodeURIComponent((tool.value||"").trim().toLowerCase())}`;
      const j = await api(url);
      st.total = j.total||0;
      meta.textContent = `run_dir: ${j.run_dir||""} · total=${st.total} · showing ${Math.min(st.limit, Math.max(0, st.total-st.offset))}/${st.total}`;
      const items = j.items||[];
      tb.innerHTML = items.map(it=>`
        <tr>
          <td><span class="vsp-badge">${esc(it.severity||"")}</span></td>
          <td>${esc(it.tool||"")}</td>
          <td>${esc(it.rule_id||"")}</td>
          <td style="max-width:360px;word-break:break-word">${esc(it.file||"")}</td>
          <td>${esc(it.line||"")}</td>
          <td style="max-width:520px;word-break:break-word">${esc(it.message||"")}</td>
        </tr>`).join("");
      const pages = Math.max(1, Math.ceil((st.total||0)/st.limit));
      const cur = Math.min(pages, Math.floor((st.offset||0)/st.limit)+1);
      page.textContent = `${cur}/${pages}`;
      $("#ds_prev").disabled = (st.offset<=0);
      $("#ds_next").disabled = (st.offset + st.limit >= st.total);
    }

    const reload = debounce(()=>{ st.offset=0; load().catch(console.error); }, 250);
    q.addEventListener("input", reload);
    sev.addEventListener("change", ()=>{ st.offset=0; load().catch(console.error); });
    tool.addEventListener("input", reload);
    lim.addEventListener("change", ()=>{ st.offset=0; load().catch(console.error); });

    $("#ds_refresh").onclick = ()=>load().catch(console.error);
    $("#ds_prev").onclick = ()=>{ st.offset=Math.max(0, st.offset-st.limit); load().catch(console.error); };
    $("#ds_next").onclick = ()=>{ st.offset=st.offset+st.limit; load().catch(console.error); };

    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
'''
write_js(ROOT/"static/js/vsp_data_source_tab_v2.js", ds)

st = r'''
/* VSP_TABS3_V2 Settings */
(() => {
  if(window.__vsp_settings_v2) return; window.__vsp_settings_v2=true;
  const { $, esc, api, ensure } = window.__vsp_tabs3_v2 || {};
  if(!ensure) return;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Settings</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">UI settings JSON (v2) · GET/POST</div>
        </div>
        <div class="vsp-row">
          <button class="vsp-btn" id="st_reload">Reload</button>
          <button class="vsp-btn" id="st_save">Save</button>
        </div>
      </div>
      <div class="vsp-card" style="margin-bottom:10px">
        <div class="vsp-muted" id="st_meta" style="font-size:12px"></div>
      </div>
      <div class="vsp-card">
        <textarea id="st_text" class="vsp-code" spellcheck="false"></textarea>
        <div id="st_msg" style="margin-top:8px;font-size:12px"></div>
      </div>
    `;

    const meta=$("#st_meta"), txt=$("#st_text"), msg=$("#st_msg");

    async function load(){
      msg.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await api("/api/vsp/ui_settings_v2");
      meta.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.settings||{}, null, 2);
      msg.innerHTML = `<span class="vsp-ok">OK</span>`;
    }

    async function save(){
      let obj;
      try{ obj = JSON.parse(txt.value||"{}"); }
      catch(e){ msg.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return; }
      msg.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await api("/api/vsp/ui_settings_v2", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({settings:obj})});
      msg.innerHTML = `<span class="vsp-ok">Saved</span> · ${esc(j.path||"")}`;
    }

    $("#st_reload").onclick = ()=>load().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);
    $("#st_save").onclick = ()=>save().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);

    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
'''
write_js(ROOT/"static/js/vsp_settings_tab_v2.js", st)

ro = r'''
/* VSP_TABS3_V2 Rule Overrides */
(() => {
  if(window.__vsp_rules_v2) return; window.__vsp_rules_v2=true;
  const { $, esc, api, ensure } = window.__vsp_tabs3_v2 || {};
  if(!ensure) return;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Rule Overrides</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Overrides JSON (v2) · stored under ui/out_ci/rule_overrides_v2</div>
        </div>
        <div class="vsp-row">
          <button class="vsp-btn" id="ro_reload">Reload</button>
          <button class="vsp-btn" id="ro_save">Save</button>
        </div>
      </div>
      <div class="vsp-card" style="margin-bottom:10px">
        <div class="vsp-muted" id="ro_meta" style="font-size:12px"></div>
        <div class="vsp-muted" style="font-size:12px;margin-top:6px">
          schema: {"rules":[ {"tool":"semgrep","rule_id":"...","action":"ignore|downgrade|upgrade","severity":"LOW","reason":"..."} ]}
        </div>
      </div>
      <div class="vsp-card">
        <textarea id="ro_text" class="vsp-code" spellcheck="false"></textarea>
        <div id="ro_msg" style="margin-top:8px;font-size:12px"></div>
      </div>
    `;

    const meta=$("#ro_meta"), txt=$("#ro_text"), msg=$("#ro_msg");

    function validate(){
      let obj;
      try{ obj = JSON.parse(txt.value||"{}"); }
      catch(e){ msg.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return null; }
      if(Array.isArray(obj)) obj={rules:obj};
      if(!obj || typeof obj!=="object" || !Array.isArray(obj.rules)){
        msg.innerHTML = `<span class="vsp-err">Invalid:</span> expect {rules:[...]} or [...]`; return null;
      }
      return obj;
    }

    async function load(){
      msg.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await api("/api/vsp/ui_rule_overrides_v2");
      meta.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.data||{rules:[]}, null, 2);
      msg.innerHTML = `<span class="vsp-ok">OK</span>`;
    }

    async function save(){
      const obj = validate(); if(!obj) return;
      msg.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await api("/api/vsp/ui_rule_overrides_v2", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(obj)});
      msg.innerHTML = `<span class="vsp-ok">Saved</span> · rules_n=${esc(j.rules_n||"")}`;
      await load();
    }

    $("#ro_reload").onclick = ()=>load().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);
    $("#ro_save").onclick = ()=>save().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);

    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
'''
write_js(ROOT/"static/js/vsp_rule_overrides_tab_v2.js", ro)

# -------------------------
# 4) Patch templates actually used by current routes (detect from gateway)
# -------------------------
wsrc = (ROOT/"wsgi_vsp_ui_gateway.py").read_text(encoding="utf-8", errors="replace")

def find_tpl(route):
    # try find function handling route + render_template("xxx")
    # simple heuristic: locate '@app.route("...")' then nearest render_template(...)
    m = re.search(r'@app\.route\(\s*[\'"]%s[\'"]\s*\)[\s\S]{0,1200}?render_template\(\s*[\'"]([^\'"]+)[\'"]' % re.escape(route), wsrc)
    return m.group(1) if m else None

routes = {
  "/data_source": ("data_source", "vsp_data_source_2025.html", ["static/js/vsp_tabs3_common_v2.js", "static/js/vsp_data_source_tab_v2.js"]),
  "/settings": ("settings", "vsp_settings_2025.html", ["static/js/vsp_tabs3_common_v2.js", "static/js/vsp_settings_tab_v2.js"]),
  "/rule_overrides": ("rule_overrides", "vsp_rule_overrides_2025.html", ["static/js/vsp_tabs3_common_v2.js", "static/js/vsp_rule_overrides_tab_v2.js"]),
}

tpl_dir = ROOT/"templates"
tpl_dir.mkdir(exist_ok=True)

for route, (tab, fallback, scripts) in routes.items():
    tpl = find_tpl(route) or fallback
    p = tpl_dir/tpl
    if not p.exists():
        # create minimal but safe; your dark css/topbar already injected by current UI stack
        p.write_text(f'<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VSP {tab}</title></head><body><div id="vsp_tab_root" data-vsp-tab="{tab}" style="padding:16px"></div>' +
                     ''.join([f'<script src="/{s}?v={int(time.time())}"></script>' for s in scripts]) +
                     '</body></html>', encoding="utf-8")
        print("[OK] created template", p)
        continue

    s = p.read_text(encoding="utf-8", errors="replace")
    if 'id="vsp_tab_root"' not in s:
        s = re.sub(r'(<body[^>]*>)', r'\1\n<div id="vsp_tab_root" data-vsp-tab="%s" style="padding:16px"></div>\n' % tab, s, flags=re.I)

    # ensure scripts injected before </body>
    for sc in scripts:
        tag = f'<script src="/{sc}"'
        if tag not in s:
            s = s.replace("</body>", f'<script src="/{sc}?v={int(time.time())}"></script>\n</body>')

    p.write_text(s, encoding="utf-8")
    print("[OK] patched template", p)

print("[DONE] tabs3 v2 patched")
PY

echo "== py_compile =="
python3 -m py_compile vsp_tabs3_ui_bp_v2.py wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart service =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2

echo "== quick verify (must not be Content-Length: 0 now) =="
for p in data_source settings rule_overrides; do
  echo "--- HEAD /$p"
  curl -fsS -I "http://127.0.0.1:8910/$p" | sed -n '1,12p'
done

echo "== verify APIs v2 =="
curl -fsS "http://127.0.0.1:8910/api/vsp/ui_findings_v2?limit=2&offset=0" | head -c 200; echo
curl -fsS "http://127.0.0.1:8910/api/vsp/ui_settings_v2" | head -c 200; echo
curl -fsS "http://127.0.0.1:8910/api/vsp/ui_rule_overrides_v2" | head -c 200; echo

echo "[OK] tabs3 v2 done"
