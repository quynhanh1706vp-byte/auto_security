#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
TPL="templates/vsp_rule_overrides_v1.html"
MARK="VSP_RULE_OVERRIDES_EDITOR_P0_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_${MARK}_${TS}"
echo "[BACKUP] $APP.bak_${MARK}_${TS}"

mkdir -p templates out_ci

cat > "$TPL" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>VSP Rule Overrides</title>
  <style>
    body{margin:0;background:#070d18;color:#dbe7ff;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial;}
    .top{position:sticky;top:0;z-index:9;background:#0b1220;border-bottom:1px solid rgba(255,255,255,.08)}
    .wrap{max-width:1400px;margin:0 auto;padding:12px 14px}
    a{color:#9fe2ff;text-decoration:none}
    .row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
    .pill{padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08)}
    .btn{padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:#dbe7ff;cursor:pointer}
    .btn:disabled{opacity:.5;cursor:not-allowed}
    textarea{width:100%;height:68vh;resize:vertical;background:#0b1220;color:#dbe7ff;border:1px solid rgba(255,255,255,.12);border-radius:14px;padding:12px;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono",monospace;font-size:13px;line-height:1.35}
    .card{margin-top:12px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:12px}
    .muted{color:#8ea3c7}
    .ok{color:#9be8a5}.bad{color:#ff6b6b}
    code{color:#9fe2ff}
  </style>
</head>
<body>
  <div class="top">
    <div class="wrap">
      <div class="row">
        <div style="font-weight:800;letter-spacing:.3px">VSP Rule Overrides</div>
        <div class="pill small muted" id="file">loading…</div>
        <div style="flex:1"></div>
        <a class="pill" href="/vsp4">Dashboard</a>
        <a class="pill" href="/runs">Runs & Reports</a>
        <a class="pill" href="/data">Data Source</a>
        <a class="pill" href="/settings">Settings</a>
      </div>
      <div class="row" style="margin-top:10px">
        <button class="btn" id="reload">Reload</button>
        <button class="btn" id="validate">Validate JSON</button>
        <button class="btn" id="save">Save</button>
        <div class="pill muted" id="status">ready</div>
      </div>
    </div>
  </div>

  <div class="wrap">
    <div class="card muted">
      Format (JSON): you can override by <code>rule_id</code> or <code>match</code>.
      Example:
      <pre style="margin:8px 0 0;white-space:pre-wrap;color:#9fb5de">{
  "enabled": true,
  "updated_by": "admin",
  "overrides": [
    { "rule_id": "semgrep.python.lang.security.audit.exec-used", "severity": "LOW", "reason": "dev sandbox" },
    { "match": { "tool": "gitleaks", "secret_type": "generic" }, "action": "suppress", "reason": "false positive" }
  ]
}</pre>
    </div>

    <div class="card">
      <textarea id="editor" spellcheck="false"></textarea>
      <div class="row" style="margin-top:10px">
        <div class="muted small" id="meta"></div>
      </div>
    </div>
  </div>

<script>
(async function(){
  const editor = document.getElementById('editor');
  const status = document.getElementById('status');
  const meta = document.getElementById('meta');
  const file = document.getElementById('file');
  const btnReload = document.getElementById('reload');
  const btnSave = document.getElementById('save');
  const btnValidate = document.getElementById('validate');

  const setStatus = (txt, ok=true) => {
    status.textContent = txt;
    status.className = 'pill ' + (ok ? 'ok' : 'bad');
  };

  function pretty(obj){ return JSON.stringify(obj, null, 2) + "\n"; }

  async function load(){
    setStatus('loading…', true);
    const res = await fetch('/api/vsp/rule_overrides');
    const j = await res.json();
    file.textContent = j.path || 'n/a';
    editor.value = pretty(j.data || {});
    meta.textContent = `who=${j.who||'n/a'}  ts=${j.ts||'n/a'}  bytes=${(editor.value||'').length}`;
    setStatus(j.ok ? 'loaded' : ('load failed: ' + (j.error||'unknown')), !!j.ok);
  }

  function validate(){
    try{
      const obj = JSON.parse(editor.value || "{}");
      setStatus('valid JSON', true);
      return obj;
    }catch(e){
      setStatus('INVALID JSON: ' + e.message, false);
      return null;
    }
  }

  async function save(){
    const obj = validate();
    if(!obj) return;
    setStatus('saving…', true);
    btnSave.disabled = true;
    try{
      const res = await fetch('/api/vsp/rule_overrides', {
        method: 'POST',
        headers: {'Content-Type':'application/json'},
        body: JSON.stringify({data: obj})
      });
      const j = await res.json();
      setStatus(j.ok ? 'saved' : ('save failed: ' + (j.error||'unknown')), !!j.ok);
      if(j.backup) meta.textContent = `saved. backup=${j.backup}`;
    } finally {
      btnSave.disabled = false;
    }
  }

  btnReload.addEventListener('click', load);
  btnValidate.addEventListener('click', validate);
  btnSave.addEventListener('click', save);

  await load();
})();
</script>
</body>
</html>
HTML

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_RULE_OVERRIDES_EDITOR_P0_V1"
app=Path("vsp_demo_app.py")
s=app.read_text(encoding="utf-8", errors="replace")

# remove older block if exists
s = re.sub(r"\n?# === VSP_RULE_OVERRIDES_EDITOR_P0_V1 ===.*?# === /VSP_RULE_OVERRIDES_EDITOR_P0_V1 ===\n?", "\n", s, flags=re.S)

# ensure imports in flask import line
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", s, flags=re.M)
need = ["jsonify","request","render_template"]
if m:
    items=[x.strip() for x in m.group(1).split(",")]
    changed=False
    for x in need:
        if x not in items:
            items.append(x); changed=True
    if changed:
        s = s[:m.start()] + "from flask import " + ", ".join(items) + s[m.end():]
else:
    s = "from flask import " + ", ".join(need) + "\n" + s

block = r'''
# === VSP_RULE_OVERRIDES_EDITOR_P0_V1 ===
from pathlib import Path as _VSP_Path
import time as _VSP_time
import json as _VSP_json

_VSP_RULE_OVR_PATH = _VSP_Path("out_ci/rule_overrides.json").resolve()
_VSP_RULE_OVR_PATH.parent.mkdir(parents=True, exist_ok=True)

def _vsp_rule_ovr_default():
    return {
        "enabled": True,
        "updated_by": "system",
        "updated_at": int(_VSP_time.time()),
        "overrides": []
    }

@app.get("/rule_overrides")
def vsp_rule_overrides_page():
    return render_template("vsp_rule_overrides_v1.html")

@app.get("/api/vsp/rule_overrides")
def vsp_api_rule_overrides_get():
    try:
        if _VSP_RULE_OVR_PATH.exists():
            data = _VSP_json.loads(_VSP_RULE_OVR_PATH.read_text(encoding="utf-8", errors="replace") or "{}")
        else:
            data = _vsp_rule_ovr_default()
        return jsonify({
            "ok": True,
            "who": "VSP_RULE_OVERRIDES_EDITOR_P0_V1",
            "ts": int(_VSP_time.time()),
            "path": str(_VSP_RULE_OVR_PATH),
            "data": data,
        })
    except Exception as e:
        return jsonify({"ok": False, "who":"VSP_RULE_OVERRIDES_EDITOR_P0_V1", "error": "READ_FAIL", "exc": str(e)}), 500

@app.post("/api/vsp/rule_overrides")
def vsp_api_rule_overrides_post():
    try:
        body = request.get_json(silent=True) or {}
        data = body.get("data")
        if data is None:
            return jsonify({"ok": False, "error": "MISSING_DATA"}), 400

        # backup old if exists
        backup = None
        if _VSP_RULE_OVR_PATH.exists():
            ts = _VSP_time.strftime("%Y%m%d_%H%M%S", _VSP_time.localtime())
            backup = str(_VSP_RULE_OVR_PATH) + ".bak_" + ts
            _VSP_Path(backup).write_text(_VSP_RULE_OVR_PATH.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")

        # stamp
        try:
            if isinstance(data, dict):
                data.setdefault("updated_at", int(_VSP_time.time()))
        except Exception:
            pass

        _VSP_RULE_OVR_PATH.write_text(_VSP_json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return jsonify({
            "ok": True,
            "who": "VSP_RULE_OVERRIDES_EDITOR_P0_V1",
            "path": str(_VSP_RULE_OVR_PATH),
            "backup": backup,
            "ts": int(_VSP_time.time()),
        })
    except Exception as e:
        return jsonify({"ok": False, "who":"VSP_RULE_OVERRIDES_EDITOR_P0_V1", "error": "WRITE_FAIL", "exc": str(e)}), 500
# === /VSP_RULE_OVERRIDES_EDITOR_P0_V1 ===
'''.strip()+"\n"

# insert before __main__ if present else append
m2 = re.search(r'^\s*if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*$', s, flags=re.M)
if m2:
    s = s[:m2.start()] + block + "\n" + s[m2.start():]
else:
    s = s + "\n\n" + block

app.write_text(s, encoding="utf-8")
print("[OK] injected rule overrides editor block")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 then verify:"
echo "  curl -sS http://127.0.0.1:8910/api/vsp/rule_overrides | jq .ok,.path,.who -C"
echo "  open http://127.0.0.1:8910/rule_overrides"
