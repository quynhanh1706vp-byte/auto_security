#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"

PYF="$(find . -maxdepth 6 -type f -name 'vsp_demo_app.py' -print -quit || true)"
JSF="$(find . -maxdepth 6 -type f -path '*/static/js/vsp_bundle_commercial_v2.js' -print -quit || true)"

[ -n "${PYF:-}" ] || { echo "[ERR] cannot find vsp_demo_app.py under $ROOT"; exit 2; }
[ -n "${JSF:-}" ] || { echo "[ERR] cannot find static/js/vsp_bundle_commercial_v2.js under $ROOT"; exit 3; }

cp -f "$PYF" "$PYF.bak_exportqa_${TS}" && echo "[BACKUP] $PYF.bak_exportqa_${TS}"
cp -f "$JSF" "$JSF.bak_exportqa_${TS}" && echo "[BACKUP] $JSF.bak_exportqa_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

py_path = Path(re.search(r"^PYF=(.*)$", Path("/proc/self/environ").read_text(errors="ignore"), re.M).group(1)) if False else None
PY

# --- patch python (backend endpoints) ---
python3 - <<'PY'
from pathlib import Path
import re

# locate files from shell by reading known paths
import os
root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
pyf = next(iter(root.rglob("vsp_demo_app.py")), None)
assert pyf, "vsp_demo_app.py not found"
s = pyf.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_EXPORT_QUICK_ACTIONS_P0_V1"
if MARK in s:
    print("[OK] backend already patched")
else:
    # ensure imports
    if "send_file" not in s:
        s = re.sub(r"from\s+flask\s+import\s+([^\n]+)",
                   lambda m: (m.group(0) if "send_file" in m.group(0) else m.group(0).rstrip()+", send_file"),
                   s, count=1)
    if "subprocess" not in s:
        s = "import subprocess\nimport glob\nimport os\nimport json\nimport urllib.request\n\n" + s

    inject = r'''
# ==== {MARK} ====
def _vsp__latest_rid_info__p0():
    """
    Returns dict from /api/vsp/latest_rid_v1:
      {{ rid, ci_run_dir, ... }}
    """
    u = "http://127.0.0.1:8910/api/vsp/latest_rid_v1"
    try:
        with urllib.request.urlopen(u, timeout=3) as r:
            return json.loads(r.read().decode("utf-8","replace"))
    except Exception as e:
        return {{"error": str(e), "rid": "", "ci_run_dir": ""}}

def _vsp__pack_report__p0(run_dir: str):
    bundle = "/home/test/Data/SECURITY_BUNDLE"
    pack = f"{bundle}/bin/pack_report.sh"
    env = os.environ.copy()
    env["RUN_DIR"] = run_dir
    env["BUNDLE"] = bundle
    # tránh pack_report tự curl lại nếu đã có RUN_DIR
    p = subprocess.run(["bash", pack], cwd=bundle, env=env, capture_output=True, text=True, timeout=180)
    # find tgz
    tgzs = sorted(glob.glob(os.path.join(run_dir, "*__REPORT.tgz")), key=lambda x: os.path.getmtime(x), reverse=True)
    tgz = tgzs[0] if tgzs else ""
    sha = os.path.join(run_dir, "SHA256SUMS.txt")
    return {{
        "ok": (p.returncode == 0 and bool(tgz)),
        "returncode": p.returncode,
        "stdout_tail": "\n".join((p.stdout or "").splitlines()[-80:]),
        "stderr_tail": "\n".join((p.stderr or "").splitlines()[-80:]),
        "tgz": tgz,
        "sha": sha if os.path.isfile(sha) else "",
    }}

@app.get("/api/vsp/pack_report_latest_v1")
def api_pack_report_latest_v1():
    info = _vsp__latest_rid_info__p0()
    run_dir = (info or {{}}).get("ci_run_dir") or ""
    rid = (info or {{}}).get("rid") or ""
    if not run_dir or not os.path.isdir(run_dir):
        return jsonify({{"ok": False, "rid": rid, "ci_run_dir": run_dir, "error": "bad ci_run_dir", "info": info}}), 400
    res = _vsp__pack_report__p0(run_dir)
    res.update({{"rid": rid, "ci_run_dir": run_dir}})
    return jsonify(res), (200 if res.get("ok") else 500)

@app.get("/api/vsp/export_report_tgz_latest_v1")
def api_export_report_tgz_latest_v1():
    info = _vsp__latest_rid_info__p0()
    run_dir = (info or {{}}).get("ci_run_dir") or ""
    rid = (info or {{}}).get("rid") or ""
    if not run_dir or not os.path.isdir(run_dir):
        return jsonify({{"ok": False, "rid": rid, "ci_run_dir": run_dir, "error": "bad ci_run_dir", "info": info}}), 400
    res = _vsp__pack_report__p0(run_dir)
    if not res.get("ok"):
        return jsonify({{"ok": False, "rid": rid, "ci_run_dir": run_dir, "error": "pack failed", **res}}), 500
    return send_file(res["tgz"], as_attachment=True, download_name=os.path.basename(res["tgz"]))

@app.get("/api/vsp/open_report_html_latest_v1")
def api_open_report_html_latest_v1():
    info = _vsp__latest_rid_info__p0()
    run_dir = (info or {{}}).get("ci_run_dir") or ""
    if not run_dir or not os.path.isdir(run_dir):
        return "bad ci_run_dir", 400
    html = os.path.join(run_dir, "report", "security_resilient.html")
    if not os.path.isfile(html):
        # try to pack (autofill will create it)
        _vsp__pack_report__p0(run_dir)
    if not os.path.isfile(html):
        return "missing security_resilient.html", 404
    return send_file(html, mimetype="text/html")

@app.get("/api/vsp/verify_report_sha_latest_v1")
def api_verify_report_sha_latest_v1():
    info = _vsp__latest_rid_info__p0()
    run_dir = (info or {{}}).get("ci_run_dir") or ""
    rid = (info or {{}}).get("rid") or ""
    if not run_dir or not os.path.isdir(run_dir):
        return jsonify({{"ok": False, "rid": rid, "ci_run_dir": run_dir, "error": "bad ci_run_dir"}}), 400
    # ensure tgz exists
    _vsp__pack_report__p0(run_dir)
    sha = os.path.join(run_dir, "SHA256SUMS.txt")
    if not os.path.isfile(sha):
        return jsonify({{"ok": False, "rid": rid, "ci_run_dir": run_dir, "error": "missing SHA256SUMS.txt"}}), 500
    p = subprocess.run(["bash","-lc", f'cd "{run_dir}" && sha256sum -c SHA256SUMS.txt'], capture_output=True, text=True, timeout=30)
    return jsonify({{
        "ok": (p.returncode == 0),
        "rid": rid,
        "ci_run_dir": run_dir,
        "returncode": p.returncode,
        "stdout": p.stdout,
        "stderr": p.stderr,
    }}), (200 if p.returncode == 0 else 500)
# ==== /{MARK} ====
'''.replace("{MARK}", MARK)

    # insert before if __name__ == "__main__" else append
    m = re.search(r"\nif\s+__name__\s*==\s*[\"']__main__[\"']\s*:\n", s)
    if m:
        s = s[:m.start()] + "\n" + inject + "\n" + s[m.start():]
    else:
        s = s + "\n" + inject + "\n"

    pyf.write_text(s, encoding="utf-8")
    print("[OK] patched backend endpoints:", MARK)

PY

# --- patch JS (floating quick actions panel) ---
python3 - <<'PY'
from pathlib import Path
import re, os

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
jsf = root / "static/js/vsp_bundle_commercial_v2.js"
if not jsf.exists():
    # fallback search
    jsf = next(iter(root.rglob("static/js/vsp_bundle_commercial_v2.js")), None)
assert jsf, "vsp_bundle_commercial_v2.js not found"

s = jsf.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_QUICK_ACTIONS_EXPORT_UI_P0_V1"
if MARK in s:
    print("[OK] quick actions already present")
else:
    block = r'''
/* {MARK}: floating quick actions (Export/Verify/Open) */
(function(){
  'use strict';
  if (window.__{MARK}__) return;
  window.__{MARK}__ = true;

  function css(txt){
    var st=document.createElement('style');
    st.setAttribute('data-vsp','{MARK}');
    st.appendChild(document.createTextNode(txt));
    document.head.appendChild(st);
  }
  function el(tag, cls, html){
    var e=document.createElement(tag);
    if(cls) e.className=cls;
    if(html!=null) e.innerHTML=html;
    return e;
  }
  function toast(msg, ok){
    var t=el('div','vspToast', msg);
    if(ok===false) t.classList.add('bad');
    document.body.appendChild(t);
    setTimeout(function(){ t.classList.add('on'); }, 10);
    setTimeout(function(){ t.classList.remove('on'); }, 2200);
    setTimeout(function(){ try{t.remove();}catch(_){} }, 2700);
  }

  css(`
    #vspQuickActions{ position:fixed; right:18px; bottom:18px; z-index:99999; width:280px;
      background:rgba(20,22,28,.92); border:1px solid rgba(255,255,255,.10);
      border-radius:16px; box-shadow:0 18px 45px rgba(0,0,0,.45);
      backdrop-filter: blur(10px); overflow:hidden; }
    #vspQuickActions .hd{ padding:12px 14px; display:flex; align-items:center; justify-content:space-between;
      border-bottom:1px solid rgba(255,255,255,.08); }
    #vspQuickActions .hd .t{ font-weight:700; font-size:12px; letter-spacing:.06em; opacity:.9; }
    #vspQuickActions .bd{ padding:12px 14px; display:grid; grid-template-columns:1fr; gap:10px; }
    #vspQuickActions button{ all:unset; cursor:pointer; padding:10px 12px; border-radius:12px;
      background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.10);
      display:flex; align-items:center; justify-content:space-between; font-weight:650; font-size:13px; }
    #vspQuickActions button:hover{ background:rgba(255,255,255,.10); }
    #vspQuickActions .muted{ opacity:.75; font-weight:600; font-size:12px; }
    #vspQuickActions .x{ cursor:pointer; opacity:.65; }
    #vspQuickActions .x:hover{ opacity:1; }
    .vspToast{ position:fixed; right:22px; bottom:320px; z-index:100000; padding:10px 12px;
      background:rgba(22,24,30,.96); border:1px solid rgba(255,255,255,.10);
      border-radius:12px; transform:translateY(10px); opacity:0; transition:all .18s ease;
      box-shadow:0 14px 35px rgba(0,0,0,.45); font-size:13px; }
    .vspToast.on{ transform:translateY(0); opacity:1; }
    .vspToast.bad{ border-color: rgba(255,80,80,.35); }
  `);

  function install(){
    if(document.getElementById('vspQuickActions')) return;

    var box=el('div','',null);
    box.id='vspQuickActions';

    var hd=el('div','hd',null);
    hd.appendChild(el('div','t','QUICK ACTIONS'));
    var close=el('div','x','✕');
    close.title='Hide';
    close.onclick=function(){ try{box.remove();}catch(_){} };
    hd.appendChild(close);

    var bd=el('div','bd',null);

    var b1=el('button','', '<span>Export TGZ</span><span class="muted">latest</span>');
    b1.onclick=function(){
      toast('Packing & downloading…');
      window.location.href='/api/vsp/export_report_tgz_latest_v1?ts='+(Date.now());
    };

    var b2=el('button','', '<span>Open HTML report</span><span class="muted">new tab</span>');
    b2.onclick=function(){
      window.open('/api/vsp/open_report_html_latest_v1?ts='+(Date.now()), '_blank');
    };

    var b3=el('button','', '<span>Verify SHA256</span><span class="muted">server</span>');
    b3.onclick=async function(){
      toast('Verifying…');
      try{
        var r=await fetch('/api/vsp/verify_report_sha_latest_v1?ts='+(Date.now()));
        var j=await r.json().catch(()=>({ok:false}));
        if(j.ok){ toast('SHA256 OK ✅', true); }
        else { toast('SHA256 FAIL ❌', false); }
      }catch(e){
        toast('Verify error ❌', false);
      }
    };

    bd.appendChild(b1); bd.appendChild(b2); bd.appendChild(b3);

    box.appendChild(hd);
    box.appendChild(bd);
    document.body.appendChild(box);
  }

  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded', install);
  } else {
    install();
  }
})();
'''.replace("{MARK}", MARK)

    s = s.rstrip() + "\n\n" + block + "\n"
    jsf.write_text(s, encoding="utf-8")
    print("[OK] appended quick actions:", MARK)

PY

echo "== syntax checks =="
python3 -m py_compile "$PYF"
node --check "$JSF"

echo "== restart UI (best-effort) =="
if [ -x "$ROOT/bin/restart_ui_8910_hardreset_p0_v1.sh" ]; then
  bash "$ROOT/bin/restart_ui_8910_hardreset_p0_v1.sh"
else
  echo "[WARN] missing restart script. Please restart gunicorn 8910 manually."
fi

echo "[NEXT] Ctrl+Shift+R on browser. You should see a floating QUICK ACTIONS panel (bottom-right)."
