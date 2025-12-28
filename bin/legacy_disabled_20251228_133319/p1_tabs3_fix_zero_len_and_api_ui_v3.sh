#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_tabs3_v3_${TS}"
echo "[BACKUP] ${W}.bak_tabs3_v3_${TS}"

mkdir -p static/js templates

python3 - <<'PY'
from pathlib import Path
import re, time, json

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
W = ROOT/"wsgi_vsp_ui_gateway.py"

# -------------------------
# 1) Blueprint v3: /api/ui/* (avoid /api/vsp catch-all)
# -------------------------
bp = ROOT/"vsp_tabs3_ui_bp_v3.py"
bp.write_text(r'''# -*- coding: utf-8 -*-
from __future__ import annotations
from flask import Blueprint, jsonify, request
from pathlib import Path
import os, json, time

vsp_tabs3_ui_bp_v3 = Blueprint("vsp_tabs3_ui_bp_v3", __name__)

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

def _latest_findings_json():
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
            fp = d/rel
            if fp.exists(): return str(d), fp
    return None, None

def _norm_sev(x):
    x = str(x or "").strip().upper()
    if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"): return x
    return {"ERROR":"HIGH","WARN":"MEDIUM","WARNING":"MEDIUM","UNKNOWN":"INFO","NONE":"INFO"}.get(x, "INFO")

def _row(d):
    return {
        "severity": _norm_sev(d.get("severity") or d.get("sev") or d.get("level")),
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

@vsp_tabs3_ui_bp_v3.get("/api/ui/findings_v2")
def api_ui_findings_v2():
    limit = int(request.args.get("limit","20") or 20)
    offset = int(request.args.get("offset","0") or 0)
    q = (request.args.get("q") or "").strip().lower()
    sev = (request.args.get("severity") or "").strip().upper()
    tool = (request.args.get("tool") or "").strip().lower()

    run_dir, fp = _latest_findings_json()
    if not fp or not fp.exists():
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
        if tool and it.get("tool","").lower() != tool: return False
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
    return jsonify({"ok": True, "items": items, "total": total, "counts": counts, "run_dir": run_dir, "ts": _now(),
                    "limit": limit, "offset": offset, "q": q, "severity": sev, "tool": tool})

def _state_dir(name):
    d = _ui_root()/"out_ci"/name
    d.mkdir(parents=True, exist_ok=True)
    return d

@vsp_tabs3_ui_bp_v3.get("/api/ui/settings_v2")
def api_ui_settings_get_v2():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    try:
        settings = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {}
    except Exception:
        settings = {}
    return jsonify({"ok": True, "settings": settings, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v3.post("/api/ui/settings_v2")
def api_ui_settings_set_v2():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    body = request.get_json(silent=True) or {}
    settings = body.get("settings", body)
    if not isinstance(settings, dict):
        return jsonify({"ok": False, "err": "settings must be object"}), 400
    p.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v3.get("/api/ui/rule_overrides_v2")
def api_ui_rules_get_v2():
    p = _state_dir("rule_overrides_v2")/"rules.json"
    try:
        data = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {"rules":[]}
    except Exception:
        data = {"rules":[]}
    if isinstance(data, list): data = {"rules": data}
    if not isinstance(data, dict): data = {"rules":[]}
    if not isinstance(data.get("rules"), list): data["rules"] = []
    return jsonify({"ok": True, "data": data, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v3.post("/api/ui/rule_overrides_v2")
def api_ui_rules_set_v2():
    p = _state_dir("rule_overrides_v2")/"rules.json"
    body = request.get_json(silent=True) or {}
    data = body.get("data", body)
    if isinstance(data, list): data = {"rules": data}
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        return jsonify({"ok": False, "err": "expect {rules:[...]} or {data:{rules:[...]}} or [...]"}), 400
    out = {"rules": [r for r in data["rules"] if isinstance(r, dict)], "updated_ts": _now()}
    p.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "rules_n": len(out["rules"]), "ts": _now()})
''', encoding="utf-8")
print("[OK] wrote", bp)

# -------------------------
# 2) Patch gateway: register bp v3 + OUTERMOST HTML body guard for 3 paths
# -------------------------
s = W.read_text(encoding="utf-8", errors="replace")

reg_marker = "VSP_TABS3_UI_BP_REGISTER_V3"
if reg_marker not in s:
    s += r'''
# --- VSP_TABS3_UI_BP_REGISTER_V3 ---
try:
    from vsp_tabs3_ui_bp_v3 import vsp_tabs3_ui_bp_v3 as _vsp_tabs3_ui_bp_v3
    if "app" in globals() and hasattr(globals()["app"], "register_blueprint"):
        globals()["app"].register_blueprint(_vsp_tabs3_ui_bp_v3)
        print("[VSP_TABS3_V3] registered blueprint: vsp_tabs3_ui_bp_v3")
except Exception as _e:
    print("[VSP_TABS3_V3] blueprint disabled:", _e)
# --- /VSP_TABS3_UI_BP_REGISTER_V3 ---
'''
    print("[OK] appended bp register v3")
else:
    print("[OK] bp register v3 already present")

guard_marker = "VSP_HTML_BODY_GUARD_OUTERMOST_V1"
if guard_marker not in s:
    s += r'''
# --- VSP_HTML_BODY_GUARD_OUTERMOST_V1 ---
try:
    from pathlib import Path as _Path
    class _VSPHtmlBodyGuard:
        def __init__(self, wsgi_app, ui_root):
            self.wsgi_app = wsgi_app
            self.ui_root = _Path(ui_root)
            self.map = {
                "/data_source": self.ui_root/"templates"/"vsp_data_source_2025.html",
                "/settings": self.ui_root/"templates"/"vsp_settings_2025.html",
                "/rule_overrides": self.ui_root/"templates"/"vsp_rule_overrides_2025.html",
            }

        def __call__(self, environ, start_response):
            path = environ.get("PATH_INFO", "") or ""
            captured = {"status": None, "headers": None}

            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers)
                return start_response(status, headers, exc_info)

            app_iter = self.wsgi_app(environ, _sr)

            # collect body
            body = b""
            try:
                for chunk in app_iter:
                    if chunk:
                        body += chunk
            finally:
                try:
                    close = getattr(app_iter, "close", None)
                    if close: close()
                except Exception:
                    pass

            status = captured["status"] or "200 OK"
            headers = captured["headers"] or []
            ct = ""
            for k,v in headers:
                if k.lower() == "content-type":
                    ct = v or ""
                    break

            # If HTML 200 and body empty => replace with template file content
            if status.startswith("200") and ct.startswith("text/html") and len(body) == 0 and path in self.map:
                fp = self.map[path]
                try:
                    if fp.exists():
                        body = fp.read_bytes()
                        # rebuild headers: remove Content-Length, then add correct
                        new_headers = [(k,v) for (k,v) in headers if k.lower() != "content-length"]
                        new_headers.append(("Content-Length", str(len(body))))
                        # replace headers by calling start_response again (WSGI allows if not committed; gunicorn ok here)
                        start_response(status, new_headers)
                        return [body]
                except Exception as _e:
                    pass

            return [body]

    if "app" in globals() and hasattr(globals()["app"], "wsgi_app"):
        globals()["app"].wsgi_app = _VSPHtmlBodyGuard(globals()["app"].wsgi_app, str(_Path(__file__).resolve().parent))
        print("[VSP_HTML_GUARD] enabled outermost guard")
except Exception as _e:
    print("[VSP_HTML_GUARD] disabled:", _e)
# --- /VSP_HTML_BODY_GUARD_OUTERMOST_V1 ---
'''
    print("[OK] appended HTML outer guard")
else:
    print("[OK] HTML outer guard already present")

W.write_text(s, encoding="utf-8")

# -------------------------
# 3) JS v3 (calls /api/ui/*)
# -------------------------
def write(p: Path, text: str):
    p.write_text(text, encoding="utf-8")
    print("[OK] wrote", p)

common = r'''/* VSP_TABS3_V3 common */
(() => {
  if (window.__vsp_tabs3_v3) return;
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
    if(document.getElementById("vsp_tabs3_v3_style")) return;
    const st=document.createElement("style");
    st.id="vsp_tabs3_v3_style";
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
  window.__vsp_tabs3_v3 = { $, esc, api, ensure };
})();
'''
write(ROOT/"static/js/vsp_tabs3_common_v3.js", common)

ds = r'''/* VSP_TABS3_V3 Data Source */
(() => {
  if(window.__vsp_ds_v3) return; window.__vsp_ds_v3=true;
  const lib = window.__vsp_tabs3_v3; if(!lib) return;
  const { $, esc, api, ensure } = lib;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;

    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Data Source</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Findings table (latest run)</div>
        </div>
        <div class="vsp-row"><button class="vsp-btn" id="ds_refresh">Refresh</button></div>
      </div>

      <div class="vsp-card" style="margin-bottom:10px">
        <div class="vsp-row">
          <input class="vsp-in" id="ds_q" placeholder="search..." style="flex:1;min-width:240px">
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
      const url = `/api/ui/findings_v2?limit=${encodeURIComponent(st.limit)}&offset=${encodeURIComponent(st.offset)}&q=${encodeURIComponent((q.value||"").trim())}&severity=${encodeURIComponent((sev.value||"").trim())}&tool=${encodeURIComponent((tool.value||"").trim().toLowerCase())}`;
      const j = await api(url);
      st.total = j.total||0;
      meta.textContent = `run_dir: ${j.run_dir||""} · total=${st.total}`;
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
write(ROOT/"static/js/vsp_data_source_tab_v3.js", ds)

st = r'''/* VSP_TABS3_V3 Settings */
(() => {
  if(window.__vsp_st_v3) return; window.__vsp_st_v3=true;
  const lib = window.__vsp_tabs3_v3; if(!lib) return;
  const { $, esc, api, ensure } = lib;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;

    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Settings</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">UI settings JSON · /api/ui/settings_v2</div>
        </div>
        <div class="vsp-row">
          <button class="vsp-btn" id="st_reload">Reload</button>
          <button class="vsp-btn" id="st_save">Save</button>
        </div>
      </div>
      <div class="vsp-card" style="margin-bottom:10px"><div class="vsp-muted" id="st_meta" style="font-size:12px"></div></div>
      <div class="vsp-card">
        <textarea id="st_text" class="vsp-code" spellcheck="false"></textarea>
        <div id="st_msg" style="margin-top:8px;font-size:12px"></div>
      </div>
    `;

    const meta=$("#st_meta"), txt=$("#st_text"), msg=$("#st_msg");

    async function load(){
      msg.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await api("/api/ui/settings_v2");
      meta.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.settings||{}, null, 2);
      msg.innerHTML = `<span class="vsp-ok">OK</span>`;
    }

    async function save(){
      let obj;
      try{ obj = JSON.parse(txt.value||"{}"); }
      catch(e){ msg.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return; }
      msg.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await api("/api/ui/settings_v2", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({settings:obj})});
      msg.innerHTML = `<span class="vsp-ok">Saved</span> · ${esc(j.path||"")}`;
    }

    $("#st_reload").onclick = ()=>load().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);
    $("#st_save").onclick = ()=>save().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);

    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
'''
write(ROOT/"static/js/vsp_settings_tab_v3.js", st)

ro = r'''/* VSP_TABS3_V3 Rule Overrides */
(() => {
  if(window.__vsp_ro_v3) return; window.__vsp_ro_v3=true;
  const lib = window.__vsp_tabs3_v3; if(!lib) return;
  const { $, esc, api, ensure } = lib;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;

    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Rule Overrides</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Overrides JSON · /api/ui/rule_overrides_v2</div>
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

    function normalize(obj){
      if(Array.isArray(obj)) obj = {rules: obj};
      if(!obj || typeof obj!=="object" || !Array.isArray(obj.rules)) throw new Error("expect {rules:[...]} or [...]");
      return obj;
    }

    async function load(){
      msg.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await api("/api/ui/rule_overrides_v2");
      meta.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.data||{rules:[]}, null, 2);
      msg.innerHTML = `<span class="vsp-ok">OK</span>`;
    }

    async function save(){
      let obj;
      try{ obj = normalize(JSON.parse(txt.value||"{}")); }
      catch(e){ msg.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return; }
      msg.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await api("/api/ui/rule_overrides_v2", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(obj)});
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
write(ROOT/"static/js/vsp_rule_overrides_tab_v3.js", ro)

# -------------------------
# 4) Patch templates to include v3 scripts (bám đúng UI hiện tại: chỉ render trong #vsp_tab_root)
# -------------------------
tpls = {
  "vsp_data_source_2025.html": ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_data_source_tab_v3.js"],
  "vsp_settings_2025.html": ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_settings_tab_v3.js"],
  "vsp_rule_overrides_2025.html": ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_rule_overrides_tab_v3.js"],
}

for name, scripts in tpls.items():
    p = ROOT/"templates"/name
    if not p.exists():
        # minimal file; outer UI/topbar (nếu có) vẫn hoạt động, JS tự render
        body = f'<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{name}</title></head><body>'
        body += f'<div id="vsp_tab_root" style="padding:16px"></div>'
        for sc in scripts:
            body += f'<script src="/{sc}?v={int(time.time())}"></script>'
        body += '</body></html>'
        p.write_text(body, encoding="utf-8")
        print("[OK] created", p)
    else:
        s = p.read_text(encoding="utf-8", errors="replace")
        if 'id="vsp_tab_root"' not in s:
            s = re.sub(r'(<body[^>]*>)', r'\1\n<div id="vsp_tab_root" style="padding:16px"></div>\n', s, flags=re.I)
        for sc in scripts:
            if f'/{sc}' not in s:
                s = s.replace("</body>", f'<script src="/{sc}?v={int(time.time())}"></script>\n</body>')
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", p)

print("[DONE] v3 patch ready")
PY

echo "== py_compile =="
python3 -m py_compile vsp_tabs3_ui_bp_v3.py wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2

echo "== verify HTML headers (Content-Length MUST be > 0 now) =="
for p in data_source settings rule_overrides; do
  echo "--- HEAD /$p"
  curl -fsS -I "http://127.0.0.1:8910/$p" | sed -n '1,12p'
done

echo "== verify /api/ui/* (MUST be ok:true, not HTTP_404_NOT_FOUND wrapper) =="
curl -fsS "http://127.0.0.1:8910/api/ui/findings_v2?limit=1&offset=0" | head -c 220; echo
curl -fsS "http://127.0.0.1:8910/api/ui/settings_v2" | head -c 220; echo
curl -fsS "http://127.0.0.1:8910/api/ui/rule_overrides_v2" | head -c 220; echo

echo "[OK] tabs3 v3 applied"
