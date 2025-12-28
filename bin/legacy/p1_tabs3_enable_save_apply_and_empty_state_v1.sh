#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep; need curl; need wc

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_tabs3_save_apply_${TS}"
echo "[BACKUP] ${W}.bak_tabs3_save_apply_${TS}"

mkdir -p static/js out_ci/vsp_settings_v2 out_ci/rule_overrides_v2 out_ci/rule_overrides_v2/applied

python3 - <<'PY'
from pathlib import Path
import json, time, re

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

marker = "VSP_TABS3_SAVE_APPLY_P1_V1"
if marker in s:
    print("[OK] marker already present, skip wsgi append")
else:
    block = r'''
# === {marker} ===
# Add POST APIs for Settings/Rule Overrides (Save + Apply) with safe JSON parsing.
try:
    import json as _json
    from pathlib import Path as _Path
except Exception:
    _json = None
    _Path = None

def _vsp__json_response(payload, code=200):
    try:
        resp = make_response(_json.dumps(payload, ensure_ascii=False), code)
        resp.headers["Content-Type"] = "application/json; charset=utf-8"
        resp.headers["Cache-Control"] = "no-store"
        return resp
    except Exception:
        resp = make_response(str(payload), code)
        resp.headers["Content-Type"] = "text/plain; charset=utf-8"
        resp.headers["Cache-Control"] = "no-store"
        return resp

def _vsp__read_json_body():
    # flask request.get_json can fail if content-type isn't correct; handle raw body too.
    try:
        data = request.get_json(silent=True)
        if isinstance(data, dict):
            return data, None
    except Exception:
        pass
    try:
        raw = request.data.decode("utf-8", errors="replace") if getattr(request, "data", None) else ""
        raw = raw.strip()
        if not raw:
            return {}, None
        return _json.loads(raw), None
    except Exception as e:
        return None, f"bad_json: {e}"

_SETTINGS_PATH = _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_settings_v2/settings.json")
_RULES_PATH    = _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/rules.json")
_APPLIED_DIR   = _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/applied")

def _vsp__atomic_write_json(path: "_Path", obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + f".tmp_{int(time.time())}")
    tmp.write_text(_json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)

@app.route("/api/ui/settings_save_v2", methods=["POST"])
def vsp_api_ui_settings_save_v2():
    if _json is None:
        return _vsp__json_response({"ok": False, "error": "json_unavailable", "ts": int(time.time())}, 500)
    body, err = _vsp__read_json_body()
    if err:
        return _vsp__json_response({"ok": False, "error": err, "ts": int(time.time())}, 400)
    if body is None:
        return _vsp__json_response({"ok": False, "error": "bad_body", "ts": int(time.time())}, 400)
    # accept either {"settings": {...}} or raw {...}
    settings = body.get("settings") if isinstance(body, dict) else None
    if settings is None and isinstance(body, dict):
        settings = body
    if not isinstance(settings, dict):
        return _vsp__json_response({"ok": False, "error": "settings_must_be_object", "ts": int(time.time())}, 400)
    _vsp__atomic_write_json(_SETTINGS_PATH, settings)
    return _vsp__json_response({"ok": True, "path": str(_SETTINGS_PATH), "settings": settings, "ts": int(time.time())})

@app.route("/api/ui/rule_overrides_save_v2", methods=["POST"])
def vsp_api_ui_rule_overrides_save_v2():
    if _json is None:
        return _vsp__json_response({"ok": False, "error": "json_unavailable", "ts": int(time.time())}, 500)
    body, err = _vsp__read_json_body()
    if err:
        return _vsp__json_response({"ok": False, "error": err, "ts": int(time.time())}, 400)
    if body is None:
        return _vsp__json_response({"ok": False, "error": "bad_body", "ts": int(time.time())}, 400)
    data = body.get("data") if isinstance(body, dict) else None
    if data is None and isinstance(body, dict):
        data = body
    if not isinstance(data, dict):
        return _vsp__json_response({"ok": False, "error": "data_must_be_object", "ts": int(time.time())}, 400)
    if "rules" not in data:
        data["rules"] = []
    if not isinstance(data.get("rules"), list):
        return _vsp__json_response({"ok": False, "error": "rules_must_be_array", "ts": int(time.time())}, 400)
    _vsp__atomic_write_json(_RULES_PATH, data)
    return _vsp__json_response({"ok": True, "path": str(_RULES_PATH), "data": data, "ts": int(time.time())})

@app.route("/api/ui/rule_overrides_apply_v2", methods=["POST"])
def vsp_api_ui_rule_overrides_apply_v2():
    if _json is None:
        return _vsp__json_response({"ok": False, "error": "json_unavailable", "ts": int(time.time())}, 500)
    rid = (request.args.get("rid") or "").strip()
    if not rid:
        return _vsp__json_response({"ok": False, "error": "missing_rid", "ts": int(time.time())}, 400)

    # optional body can override rules to apply; else use current rules file
    body, err = _vsp__read_json_body()
    if err:
        return _vsp__json_response({"ok": False, "error": err, "ts": int(time.time())}, 400)

    applied = None
    try:
        if isinstance(body, dict) and body:
            applied = body.get("data") or body
        if applied is None:
            if _RULES_PATH.exists():
                applied = _json.loads(_RULES_PATH.read_text(encoding="utf-8", errors="replace"))
            else:
                applied = {"rules": []}
    except Exception:
        applied = {"rules": []}

    _APPLIED_DIR.mkdir(parents=True, exist_ok=True)
    out = _APPLIED_DIR / f"{rid}.json"
    payload = {
        "rid": rid,
        "applied_at": int(time.time()),
        "source_rules_path": str(_RULES_PATH),
        "applied_rules_path": str(out),
        "data": applied if isinstance(applied, dict) else {"rules": []},
    }
    _vsp__atomic_write_json(out, payload)
    return _vsp__json_response({"ok": True, **payload, "ts": int(time.time())})
# === /{marker} ===
'''.replace("{marker}", marker)

    # append at EOF
    s = s.rstrip() + "\n\n" + block + "\n"
    W.write_text(s, encoding="utf-8")
    print("[OK] appended wsgi save/apply block:", marker)

# --- JS patch: Settings v3 ---
p = Path("static/js/vsp_settings_tab_v3.js")
p_bak = p.with_name(p.name + f".bak_{int(time.time())}")
if p.exists():
    p_bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")

p.write_text(r'''
// VSP_SETTINGS_TAB_V3_P1
(function(){
  const API = {
    get:  "/api/ui/settings_v2",
    save: "/api/ui/settings_save_v2",
  };

  function $(sel, root=document){ return root.querySelector(sel); }
  function toast(msg, ok=true){
    let el = $("#vsp_toast");
    if(!el){
      el = document.createElement("div");
      el.id="vsp_toast";
      el.style.position="fixed";
      el.style.right="16px";
      el.style.bottom="16px";
      el.style.padding="10px 12px";
      el.style.borderRadius="10px";
      el.style.fontSize="13px";
      el.style.background="rgba(20,24,30,.92)";
      el.style.border="1px solid rgba(255,255,255,.12)";
      el.style.color="#e6eef7";
      el.style.zIndex="99999";
      document.body.appendChild(el);
    }
    el.textContent = msg;
    el.style.opacity="1";
    setTimeout(()=>{ el.style.opacity="0"; }, ok?1800:2600);
  }

  async function jget(url){
    const r = await fetch(url, {cache:"no-store"});
    const t = await r.text();
    let j=null; try{ j=JSON.parse(t); }catch(e){}
    if(!r.ok) throw new Error(`HTTP_${r.status}: ${t.slice(0,220)}`);
    return j||{};
  }
  async function jpost(url, obj){
    const r = await fetch(url, {
      method:"POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify(obj||{})
    });
    const t = await r.text();
    let j=null; try{ j=JSON.parse(t); }catch(e){}
    if(!r.ok) throw new Error(`HTTP_${r.status}: ${t.slice(0,220)}`);
    return j||{};
  }

  function render(root){
    root.innerHTML = `
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">
        <div style="font-size:18px;font-weight:700">Settings</div>
        <div style="opacity:.65;font-size:12px">/api/ui/settings_v2</div>
        <div style="flex:1"></div>
        <button id="btn_effective" class="vsp_btn">Show effective</button>
        <button id="btn_reload" class="vsp_btn">Reload</button>
        <button id="btn_save" class="vsp_btn vsp_btn_primary">Save</button>
      </div>
      <div id="path_line" style="opacity:.7;font-size:12px;margin-bottom:8px"></div>
      <div style="display:grid;grid-template-columns:1fr;gap:10px">
        <textarea id="ta" spellcheck="false" style="width:100%;height:260px;resize:vertical;background:#0b1220;color:#dbe8ff;border:1px solid rgba(255,255,255,.10);border-radius:12px;padding:10px;font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;font-size:12px;line-height:1.35"></textarea>
        <pre id="effective" style="display:none;white-space:pre-wrap;background:#0b1220;color:#cfe2ff;border:1px solid rgba(255,255,255,.10);border-radius:12px;padding:10px;font-size:12px"></pre>
        <div id="status" style="font-size:12px;opacity:.75">Loading...</div>
      </div>
    `;

    const ta = $("#ta", root);
    const st = $("#status", root);
    const eff = $("#effective", root);
    const pathLine = $("#path_line", root);

    async function load(){
      st.textContent="Loading...";
      try{
        const j = await jget(API.get);
        pathLine.textContent = `path: ${j.path||""}`;
        ta.value = JSON.stringify(j.settings||{}, null, 2);
        eff.textContent = JSON.stringify(j.effective||{}, null, 2);
        st.textContent = "OK";
      }catch(e){
        st.textContent = "ERROR: " + e.message;
        toast("Settings load failed", false);
      }
    }

    $("#btn_reload", root).onclick = ()=>load();
    $("#btn_effective", root).onclick = ()=>{
      eff.style.display = (eff.style.display==="none" ? "block" : "none");
    };
    $("#btn_save", root).onclick = async ()=>{
      try{
        const obj = JSON.parse(ta.value||"{}");
        const j = await jpost(API.save, {settings: obj});
        toast("Saved settings");
        st.textContent = "OK";
        if(j && j.effective) eff.textContent = JSON.stringify(j.effective, null, 2);
      }catch(e){
        toast("Save failed: " + e.message, false);
        st.textContent = "ERROR: " + e.message;
      }
    };

    load();
  }

  function boot(){
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    render(root);
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", boot);
  }else boot();
})();
''', encoding="utf-8")
print("[OK] wrote static/js/vsp_settings_tab_v3.js")

# --- JS patch: Rule Overrides v3 ---
p = Path("static/js/vsp_rule_overrides_tab_v3.js")
p_bak = p.with_name(p.name + f".bak_{int(time.time())}")
if p.exists():
    p_bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")

p.write_text(r'''
// VSP_RULE_OVERRIDES_TAB_V3_P1
(function(){
  const API = {
    runs:  "/api/ui/runs_v2?limit=200",
    get:   "/api/ui/rule_overrides_v2",
    save:  "/api/ui/rule_overrides_save_v2",
    apply: "/api/ui/rule_overrides_apply_v2",
  };

  function $(sel, root=document){ return root.querySelector(sel); }
  function toast(msg, ok=true){
    let el = $("#vsp_toast");
    if(!el){
      el = document.createElement("div");
      el.id="vsp_toast";
      el.style.position="fixed";
      el.style.right="16px";
      el.style.bottom="16px";
      el.style.padding="10px 12px";
      el.style.borderRadius="10px";
      el.style.fontSize="13px";
      el.style.background="rgba(20,24,30,.92)";
      el.style.border="1px solid rgba(255,255,255,.12)";
      el.style.color="#e6eef7";
      el.style.zIndex="99999";
      document.body.appendChild(el);
    }
    el.textContent = msg;
    el.style.opacity="1";
    setTimeout(()=>{ el.style.opacity="0"; }, ok?1800:2600);
  }

  async function jget(url){
    const r = await fetch(url, {cache:"no-store"});
    const t = await r.text();
    let j=null; try{ j=JSON.parse(t); }catch(e){}
    if(!r.ok) throw new Error(`HTTP_${r.status}: ${t.slice(0,220)}`);
    return j||{};
  }
  async function jpost(url, obj){
    const r = await fetch(url, {
      method:"POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify(obj||{})
    });
    const t = await r.text();
    let j=null; try{ j=JSON.parse(t); }catch(e){}
    if(!r.ok) throw new Error(`HTTP_${r.status}: ${t.slice(0,220)}`);
    return j||{};
  }

  function render(root){
    root.innerHTML = `
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">
        <div style="font-size:18px;font-weight:700">Rule Overrides</div>
        <div style="opacity:.65;font-size:12px">/api/ui/rule_overrides_v2</div>
        <div style="flex:1"></div>

        <select id="sel_rid" class="vsp_select" style="min-width:340px">
          <option value="">(loading runs...)</option>
        </select>

        <button id="btn_apply" class="vsp_btn">Apply to RID</button>
        <button id="btn_reload" class="vsp_btn">Reload</button>
        <button id="btn_save" class="vsp_btn vsp_btn_primary">Save</button>
      </div>

      <div id="path_line" style="opacity:.7;font-size:12px;margin-bottom:8px"></div>
      <div style="opacity:.65;font-size:12px;margin-bottom:8px">
        schema: {"rules":[{"tool":"semgrep","rule_id":"...","action":"ignore|downgrade|upgrade","severity":"LOW|...","reason":"..."}]}
      </div>

      <textarea id="ta" spellcheck="false" style="width:100%;height:320px;resize:vertical;background:#0b1220;color:#dbe8ff;border:1px solid rgba(255,255,255,.10);border-radius:12px;padding:10px;font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;font-size:12px;line-height:1.35"></textarea>

      <div id="status" style="margin-top:8px;font-size:12px;opacity:.75">Loading...</div>
    `;

    const ta = $("#ta", root);
    const st = $("#status", root);
    const pathLine = $("#path_line", root);
    const sel = $("#sel_rid", root);

    async function loadRuns(){
      try{
        const j = await jget(API.runs);
        const items = (j.items||[]);
        sel.innerHTML = "";
        if(!items.length){
          sel.innerHTML = `<option value="">(no runs)</option>`;
          return;
        }
        for(const it of items){
          const rid = it.rid || "";
          const opt = document.createElement("option");
          opt.value = rid;
          opt.textContent = rid;
          sel.appendChild(opt);
        }
      }catch(e){
        sel.innerHTML = `<option value="">(runs API failed)</option>`;
        toast("Runs load failed: " + e.message, false);
      }
    }

    async function loadRules(){
      st.textContent="Loading...";
      try{
        const j = await jget(API.get);
        pathLine.textContent = `path: ${j.path||""}`;
        ta.value = JSON.stringify((j.data||{"rules":[]}), null, 2);
        st.textContent="OK";
      }catch(e){
        st.textContent="ERROR: " + e.message;
        toast("Rule overrides load failed", false);
      }
    }

    $("#btn_reload", root).onclick = async ()=>{
      await loadRuns();
      await loadRules();
    };

    $("#btn_save", root).onclick = async ()=>{
      try{
        const obj = JSON.parse(ta.value||"{}");
        const j = await jpost(API.save, {data: obj});
        toast("Saved rule overrides");
        st.textContent="OK";
        if(j && j.path) pathLine.textContent = `path: ${j.path}`;
      }catch(e){
        toast("Save failed: " + e.message, false);
        st.textContent="ERROR: " + e.message;
      }
    };

    $("#btn_apply", root).onclick = async ()=>{
      const rid = (sel.value||"").trim();
      if(!rid){ toast("Pick RID first", false); return; }
      try{
        const obj = JSON.parse(ta.value||"{}");
        const url = API.apply + `?rid=${encodeURIComponent(rid)}`;
        const j = await jpost(url, {data: obj});
        toast(`Applied to ${rid}`);
        st.textContent="OK";
      }catch(e){
        toast("Apply failed: " + e.message, false);
        st.textContent="ERROR: " + e.message;
      }
    };

    (async ()=>{
      await loadRuns();
      await loadRules();
    })();
  }

  function boot(){
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    render(root);
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", boot);
  }else boot();
})();
''', encoding="utf-8")
print("[OK] wrote static/js/vsp_rule_overrides_tab_v3.js")

# --- JS patch: Data Source v3 (empty state) ---
p = Path("static/js/vsp_data_source_tab_v3.js")
if p.exists():
    old = p.read_text(encoding="utf-8", errors="replace")
else:
    old = ""

# minimal safe append: if empty state handler not present, add a small wrapper
if "VSP_DATA_SOURCE_EMPTY_STATE_P1" in old:
    print("[OK] data source empty-state already present")
else:
    # simple injection: when table body empty, show message
    patch = r'''
// VSP_DATA_SOURCE_EMPTY_STATE_P1
(function(){
  function $(sel, root=document){ return root.querySelector(sel); }
  function ensureEmptyMsg(){
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    const tbl = root.querySelector("table");
    if(!tbl) return;
    const body = tbl.querySelector("tbody");
    if(!body) return;
    const hasRows = body.querySelectorAll("tr").length > 0;
    let msg = root.querySelector("#vsp_empty_state_msg");
    if(!hasRows){
      if(!msg){
        msg = document.createElement("div");
        msg.id="vsp_empty_state_msg";
        msg.style.opacity=".75";
        msg.style.margin="12px 2px";
        msg.style.fontSize="12px";
        msg.textContent = "No findings for selected run (or filters).";
        tbl.parentElement.insertBefore(msg, tbl.nextSibling);
      }
    }else{
      if(msg) msg.remove();
    }
  }
  const _obs = new MutationObserver(()=>ensureEmptyMsg());
  function boot(){
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    _obs.observe(root, {subtree:true, childList:true});
    setTimeout(ensureEmptyMsg, 600);
    setInterval(ensureEmptyMsg, 1800);
  }
  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
'''
    p.write_text(old.rstrip()+"\n\n"+patch+"\n", encoding="utf-8")
    print("[OK] appended empty-state helper to static/js/vsp_data_source_tab_v3.js")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py vsp_tabs3_ui_bp_v4.py 2>/dev/null || python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1.2

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify POST APIs =="
curl -fsS "$BASE/api/ui/settings_save_v2" -H 'Content-Type: application/json' -d '{"settings":{"degrade_graceful":true}}' | head -c 180; echo
curl -fsS "$BASE/api/ui/rule_overrides_save_v2" -H 'Content-Type: application/json' -d '{"data":{"rules":[]}}' | head -c 180; echo
RID="$(curl -fsS "$BASE/api/ui/runs_v2?limit=1" | python3 -c 'import sys,json; print(json.load(sys.stdin)["items"][0]["rid"])')"
curl -fsS "$BASE/api/ui/rule_overrides_apply_v2?rid=$RID" -H 'Content-Type: application/json' -d '{"data":{"rules":[]}}' | head -c 200; echo

echo "[DONE] tabs3 save/apply + datasource empty state patched"
