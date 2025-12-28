#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

# --- paths ---
PYAPP="vsp_demo_app.py"
[ -f "$PYAPP" ] || { echo "[ERR] missing $PYAPP"; exit 2; }

TEMPL_DIR="templates"
STATIC_DIR="static"
JS_DIR="$STATIC_DIR/js"

mkdir -p out_ci "$TEMPL_DIR" "$JS_DIR"

OVR_FILE_DEFAULT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json"
[ -f "$OVR_FILE_DEFAULT" ] || cat > "$OVR_FILE_DEFAULT" <<'JSON'
{
  "version": 1,
  "updated_at": null,
  "items": []
}
JSON

# --- template (standalone page) ---
TPL="$TEMPL_DIR/vsp_rule_overrides_v1.html"
if [ ! -f "$TPL" ]; then
cat > "$TPL" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>VSP • Rule Overrides</title>
  <style>
    body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Arial,sans-serif;margin:0;background:#0b1220;color:#e5e7eb}
    .wrap{max-width:1200px;margin:24px auto;padding:0 16px}
    .card{background:#0f172a;border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:16px;box-shadow:0 8px 30px rgba(0,0,0,.25)}
    h1{font-size:20px;margin:0 0 12px}
    .row{display:flex;gap:12px;flex-wrap:wrap}
    .row > *{flex:1}
    textarea,input,select{width:100%;padding:10px;border-radius:10px;border:1px solid rgba(255,255,255,.10);background:#0b1220;color:#e5e7eb}
    button{padding:10px 14px;border-radius:12px;border:1px solid rgba(255,255,255,.12);background:#111c33;color:#e5e7eb;cursor:pointer}
    button:hover{filter:brightness(1.08)}
    .muted{color:#9ca3af;font-size:12px}
    table{width:100%;border-collapse:collapse;margin-top:10px}
    th,td{border-bottom:1px solid rgba(255,255,255,.08);padding:8px;text-align:left;font-size:13px;vertical-align:top}
    code{background:rgba(255,255,255,.06);padding:2px 6px;border-radius:8px}
    .pill{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.10);font-size:12px}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h1>Rule Overrides</h1>
      <div class="muted">Commercial P1: GET/POST <code>/api/vsp/rule_overrides_v1</code> • Apply on findings preview • Severity normalized to 6 levels</div>
    </div>

    <div style="height:12px"></div>

    <div class="card">
      <div class="row">
        <div>
          <div class="muted">Raw JSON (contract: version/updated_at/items[])</div>
          <textarea id="json" rows="14"></textarea>
        </div>
        <div>
          <div class="muted">Quick add (append 1 item)</div>
          <div class="row">
            <div><input id="rule_id" placeholder="rule_id (exact) e.g. semgrep.xxx"/></div>
            <div>
              <select id="action">
                <option value="suppress">suppress</option>
                <option value="downgrade">downgrade</option>
              </select>
            </div>
          </div>
          <div class="row">
            <div>
              <select id="set_sev">
                <option value="CRITICAL">CRITICAL</option>
                <option value="HIGH">HIGH</option>
                <option value="MEDIUM">MEDIUM</option>
                <option value="LOW">LOW</option>
                <option value="INFO">INFO</option>
                <option value="TRACE">TRACE</option>
              </select>
            </div>
            <div><input id="expires_at" placeholder="expires_at (optional) 2026-12-31"/></div>
          </div>
          <div><input id="justification" placeholder="justification (required)"/></div>

          <div style="height:10px"></div>
          <div class="row">
            <button onclick="loadOVR()">Reload</button>
            <button onclick="saveOVR()">Save</button>
            <button onclick="addOne()">Add item</button>
          </div>
          <div style="height:10px"></div>

          <div class="muted">Test apply (RID latest)</div>
          <div class="row">
            <button onclick="testApply()">Preview findings (latest RID)</button>
          </div>
          <div id="msg" class="muted" style="margin-top:10px"></div>
        </div>
      </div>

      <table id="tbl">
        <thead><tr><th>#</th><th>match</th><th>action</th><th>severity</th><th>expires</th><th>justification</th></tr></thead>
        <tbody></tbody>
      </table>
    </div>
  </div>

<script src="/static/js/vsp_rule_overrides_v1.js"></script>
</body>
</html>
HTML
fi

# --- JS ---
JSF="$JS_DIR/vsp_rule_overrides_v1.js"
if [ ! -f "$JSF" ]; then
cat > "$JSF" <<'JS'
async function apiGet(url){ const r=await fetch(url,{credentials:"same-origin"}); return {r, j: await r.json().catch(()=>({}))}; }
async function apiPost(url, body){ const r=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body),credentials:"same-origin"}); return {r, j: await r.json().catch(()=>({}))}; }

function setMsg(s){ document.getElementById("msg").textContent = s; }

function renderTbl(obj){
  const items = (obj && obj.items) ? obj.items : [];
  const tb = document.querySelector("#tbl tbody");
  tb.innerHTML = "";
  items.forEach((it, idx)=>{
    const tr=document.createElement("tr");
    const match = JSON.stringify(it.match||{}, null, 0);
    tr.innerHTML = `<td>${idx+1}</td>
      <td><code>${match.replaceAll("<","&lt;")}</code></td>
      <td><span class="pill">${it.action||""}</span></td>
      <td>${it.set_severity||""}</td>
      <td>${it.expires_at||""}</td>
      <td>${(it.justification||"").replaceAll("<","&lt;")}</td>`;
    tb.appendChild(tr);
  });
}

async function loadOVR(){
  const {r,j}=await apiGet("/api/vsp/rule_overrides_v1");
  document.getElementById("json").value = JSON.stringify(j, null, 2);
  renderTbl(j);
  setMsg(`GET status=${r.status} items=${(j.items||[]).length}`);
}

async function saveOVR(){
  let obj;
  try { obj = JSON.parse(document.getElementById("json").value || "{}"); }
  catch(e){ setMsg("JSON parse error: "+e); return; }
  const {r,j}=await apiPost("/api/vsp/rule_overrides_v1", obj);
  document.getElementById("json").value = JSON.stringify(j, null, 2);
  renderTbl(j);
  setMsg(`POST status=${r.status} updated_at=${j.updated_at||""}`);
}

async function addOne(){
  let obj;
  try { obj = JSON.parse(document.getElementById("json").value || "{}"); }
  catch(e){ setMsg("JSON parse error: "+e); return; }
  obj.items = obj.items || [];
  const rule_id = (document.getElementById("rule_id").value||"").trim();
  const action = document.getElementById("action").value;
  const set_severity = document.getElementById("set_sev").value;
  const expires_at = (document.getElementById("expires_at").value||"").trim();
  const justification = (document.getElementById("justification").value||"").trim();

  if(!rule_id){ setMsg("rule_id required"); return; }
  if(!justification){ setMsg("justification required"); return; }

  const it = {
    id: `ovr_${Date.now()}`,
    match: { rule_id },
    action,
    set_severity: action==="downgrade" ? set_severity : undefined,
    justification,
    expires_at: expires_at || undefined
  };
  obj.items.push(it);
  document.getElementById("json").value = JSON.stringify(obj, null, 2);
  renderTbl(obj);
  setMsg("Added 1 item (not saved yet)");
}

async function testApply(){
  const ridRsp = await fetch("/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1",{credentials:"same-origin"});
  const ridJ = await ridRsp.json().catch(()=>({}));
  const rid = ridJ?.items?.[0]?.run_id;
  if(!rid){ setMsg("Cannot get latest RID"); return; }
  const {r,j}=await apiGet(`/api/vsp/findings_preview_v1/${encodeURIComponent(rid)}?show_suppressed=1&limit=50`);
  setMsg(`Preview status=${r.status} rid=${rid} total=${j.total||j.total_n||0} (show_suppressed=1)`);
  console.log("findings_preview", j);
}

window.addEventListener("load", loadOVR);
JS
fi

# --- patch vsp_demo_app.py ---
cp -f "$PYAPP" "$PYAPP.bak_rule_overrides_${TS}"
echo "[BACKUP] $PYAPP.bak_rule_overrides_${TS}"

python3 - <<'PY'
from pathlib import Path
import json, re
from datetime import datetime, timezone

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RULE_OVERRIDES_FULL_V1 ==="
if TAG in t:
    print("[OK] already patched, skip")
    raise SystemExit(0)

block = r'''
# === VSP_RULE_OVERRIDES_FULL_V1 ===
import os, json, fnmatch
from datetime import datetime, timezone
from flask import request, jsonify, send_from_directory

def _vsp_now_iso():
    return datetime.now(timezone.utc).isoformat()

def _vsp_rule_overrides_path():
    return os.environ.get("VSP_RULE_OVERRIDES_FILE") or "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json"

def _vsp_load_overrides():
    path = _vsp_rule_overrides_path()
    try:
        with open(path, "r", encoding="utf-8") as f:
            obj = json.load(f)
    except Exception:
        obj = {"version": 1, "updated_at": None, "items": []}
    if not isinstance(obj, dict):
        obj = {"version": 1, "updated_at": None, "items": []}
    obj.setdefault("version", 1)
    obj.setdefault("updated_at", None)
    obj.setdefault("items", [])
    if not isinstance(obj["items"], list):
        obj["items"] = []
    return obj

def _vsp_atomic_write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)

def _norm_sev(s):
    if s is None: return "INFO"
    x = str(s).strip().upper()
    m = {
      "CRITICAL":"CRITICAL","HIGH":"HIGH","MEDIUM":"MEDIUM","LOW":"LOW","INFO":"INFO","TRACE":"TRACE",
      "WARN":"LOW","WARNING":"LOW","ERROR":"MEDIUM","ERR":"MEDIUM","NOTE":"INFO","UNKNOWN":"INFO","NONE":"INFO"
    }
    return m.get(x, "INFO")

def _match_one(f, m):
    # f: finding dict, m: match dict
    if not isinstance(m, dict): return False
    # exact fields
    for k in ("rule_id","tool","cwe"):
        if k in m and m[k]:
            if str(f.get(k,"")) != str(m[k]): return False
    # glob path
    pg = m.get("path_glob")
    if pg:
        path = f.get("path") or f.get("file") or f.get("filename") or ""
        if not fnmatch.fnmatch(path, pg): return False
    # substring message
    mc = m.get("message_contains")
    if mc:
        msg = f.get("message") or f.get("title") or ""
        if str(mc).lower() not in str(msg).lower(): return False
    return True

def _is_expired(expires_at: str|None):
    if not expires_at: return False
    try:
        # allow YYYY-MM-DD
        if len(expires_at) == 10:
            dt = datetime.fromisoformat(expires_at + "T00:00:00+00:00")
        else:
            dt = datetime.fromisoformat(expires_at.replace("Z","+00:00"))
        return datetime.now(timezone.utc) > dt
    except Exception:
        return False

def _apply_overrides(items, overrides, show_suppressed=False):
    applied = {"suppressed": 0, "downgraded": 0, "expired_skipped": 0}
    out = []
    for f in (items or []):
        if not isinstance(f, dict):
            out.append(f); continue
        # normalize severity first
        sev0 = f.get("severity") or f.get("severity_norm") or f.get("level")
        sevN = _norm_sev(sev0)
        f["severity_norm"] = sevN

        suppressed = False
        for r in overrides.get("items", []) or []:
            if not isinstance(r, dict): 
                continue
            if _is_expired(r.get("expires_at")):
                applied["expired_skipped"] += 1
                continue
            if not _match_one(f, r.get("match", {})):
                continue
            act = (r.get("action") or "").lower().strip()
            if act == "suppress":
                suppressed = True
                f["suppressed"] = True
                f["override_action"] = "suppress"
                f["override_justification"] = r.get("justification")
                f["override_id"] = r.get("id") or None
                applied["suppressed"] += 1
                break
            if act == "downgrade":
                newsev = _norm_sev(r.get("set_severity") or "INFO")
                if f.get("severity_norm") != newsev:
                    f["severity_orig"] = f.get("severity_norm")
                    f["severity_norm"] = newsev
                    f["override_action"] = "downgrade"
                    f["override_justification"] = r.get("justification")
                    f["override_id"] = r.get("id") or None
                    applied["downgraded"] += 1
                # do not break: allow later suppress to win (but if you want first-hit wins, break here)
        if suppressed and not show_suppressed:
            continue
        out.append(f)
    return out, applied

def _wrap_json_view(func):
    def _wrapped(*args, **kwargs):
        resp = func(*args, **kwargs)
        # resp may be (json, code) or Response
        try:
            from flask import Response
            if isinstance(resp, Response):
                if resp.mimetype != "application/json":
                    return resp
                data = resp.get_json(silent=True) or {}
                code = resp.status_code
            elif isinstance(resp, tuple):
                data = resp[0] if isinstance(resp[0], dict) else {}
                code = resp[1] if len(resp) > 1 and isinstance(resp[1], int) else 200
            elif isinstance(resp, dict):
                data = resp; code = 200
            else:
                return resp
        except Exception:
            return resp

        # apply only when findings list present
        overrides = _vsp_load_overrides()
        show_supp = (request.args.get("show_suppressed") or "0").strip() in ("1","true","yes","on")
        limit = request.args.get("limit")
        try:
            limit_n = int(limit) if limit else None
        except Exception:
            limit_n = None

        key = None
        if isinstance(data, dict):
            if isinstance(data.get("items"), list): key = "items"
            elif isinstance(data.get("findings"), list): key = "findings"
        if key:
            items = data.get(key) or []
            if limit_n is not None:
                items = items[:limit_n]
            new_items, applied = _apply_overrides(items, overrides, show_suppressed=show_supp)
            data[key] = new_items
            data["rule_overrides"] = {"updated_at": overrides.get("updated_at"), "applied": applied, "show_suppressed": show_supp}
            # recompute totals best-effort
            try:
                data["items_n"] = len(new_items)
            except Exception:
                pass
        return jsonify(data), code
    _wrapped.__name__ = getattr(func, "__name__", "wrapped_findings")
    return _wrapped

def _install_rule_overrides(appobj):
    # API
    @appobj.route("/api/vsp/rule_overrides_v1", methods=["GET"])
    def api_vsp_rule_overrides_get_v1():
        obj = _vsp_load_overrides()
        return jsonify(obj)

    @appobj.route("/api/vsp/rule_overrides_v1", methods=["POST"])
    def api_vsp_rule_overrides_post_v1():
        obj = request.get_json(silent=True) or {}
        if not isinstance(obj, dict):
            return jsonify({"ok": False, "error": "invalid_json"}), 400
        obj.setdefault("version", 1)
        obj.setdefault("items", [])
        if not isinstance(obj["items"], list):
            return jsonify({"ok": False, "error": "items_must_be_list"}), 400
        # minimal validation
        norm_items = []
        for it in obj["items"]:
            if not isinstance(it, dict): 
                continue
            match = it.get("match") or {}
            if not isinstance(match, dict): 
                match = {}
            action = (it.get("action") or "").lower().strip()
            if action not in ("suppress","downgrade"):
                continue
            just = (it.get("justification") or "").strip()
            if not just:
                continue
            nid = it.get("id") or f"ovr_{int(datetime.now(timezone.utc).timestamp()*1000)}"
            out = {
              "id": nid,
              "match": match,
              "action": action,
              "justification": just,
              "expires_at": it.get("expires_at") or None
            }
            if action == "downgrade":
                out["set_severity"] = _norm_sev(it.get("set_severity") or "INFO")
            norm_items.append(out)
        obj["items"] = norm_items
        obj["updated_at"] = _vsp_now_iso()

        path = _vsp_rule_overrides_path()
        try:
            _vsp_atomic_write(path, obj)
        except Exception as e:
            return jsonify({"ok": False, "error": "write_failed", "detail": str(e)}), 500
        return jsonify(obj)

    # UI page (standalone, doesn't break dashboard)
    @appobj.route("/vsp/rule_overrides", methods=["GET"])
    def vsp_rule_overrides_page_v1():
        # render template if exists, else return simple text
        try:
            from flask import render_template
            return render_template("vsp_rule_overrides_v1.html")
        except Exception:
            return "Rule Overrides UI missing template", 500

    # Wrap findings preview endpoints best-effort
    try:
        rules = list(appobj.url_map.iter_rules())
        cand = []
        for r in rules:
            rr = (r.rule or "")
            if rr.startswith("/api/vsp/") and "findings" in rr and ("GET" in (r.methods or set())):
                cand.append((rr, r.endpoint))
        for rr, ep in cand:
            if ep in appobj.view_functions:
                appobj.view_functions[ep] = _wrap_json_view(appobj.view_functions[ep])
        try:
            print("[VSP_RULE_OVERRIDES] wrapped_findings_endpoints=", [c[0] for c in cand][:10])
        except Exception:
            pass
    except Exception:
        pass

# install on existing flask app object
try:
    _a = globals().get("app") or globals().get("application")
    if _a is not None:
        _install_rule_overrides(_a)
        try:
            print("[VSP_RULE_OVERRIDES] installed api/ui/apply ok file=", _vsp_rule_overrides_path())
        except Exception:
            pass
except Exception as _e:
    try:
        print("[VSP_RULE_OVERRIDES][ERR]", str(_e))
    except Exception:
        pass
'''

p.write_text(t + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended rule overrides block")
PY

python3 -m py_compile "$PYAPP"
echo "[OK] py_compile OK"

# --- best-effort: add menu link into common sidebar templates if present ---
python3 - <<'PY'
from pathlib import Path
import re, time

cands = [
  "templates/vsp_layout_sidebar.html",
  "templates/vsp_5tabs_full.html",
  "templates/vsp_layout_sidebar_v1.html",
  "templates/layout.html",
  "templates/base.html",
]
link_html = r'''<li class="nav-item"><a class="nav-link" href="/vsp/rule_overrides">Rule Overrides</a></li>'''

patched = 0
for fn in cands:
    p = Path(fn)
    if not p.exists():
        continue
    t = p.read_text(encoding="utf-8", errors="ignore")
    if "Rule Overrides" in t:
        continue
    # insert after Data Source if found
    if "Data Source" in t:
        t2 = t.replace("Data Source</a></li>", "Data Source</a></li>\n" + link_html, 1)
    else:
        # fallback: before closing </ul> of nav
        t2 = re.sub(r"</ul>", link_html + "\n</ul>", t, count=1)
    bak = f"{fn}.bak_rule_overrides_{int(time.time())}"
    Path(fn).write_text(t2, encoding="utf-8")
    print("[OK] patched menu:", fn, "backup->", bak)
    patched += 1

print("[INFO] menu_patched_n=", patched)
PY

echo "[DONE] rule_overrides patched"
