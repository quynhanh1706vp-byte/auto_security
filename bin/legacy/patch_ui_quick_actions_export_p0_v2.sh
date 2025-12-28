#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
TS="$(date +%Y%m%d_%H%M%S)"

PYF="$(find . -maxdepth 8 -type f -name 'vsp_demo_app.py' -print -quit || true)"
JSF="$(find . -maxdepth 8 -type f -path '*/static/js/vsp_bundle_commercial_v2.js' -print -quit || true)"
[ -n "${PYF:-}" ] || { echo "[ERR] cannot find vsp_demo_app.py"; exit 2; }
[ -n "${JSF:-}" ] || { echo "[ERR] cannot find vsp_bundle_commercial_v2.js"; exit 3; }

cp -f "$PYF" "$PYF.bak_exportqa_v2_${TS}" && echo "[BACKUP] $PYF.bak_exportqa_v2_${TS}"
cp -f "$JSF" "$JSF.bak_exportqa_v2_${TS}" && echo "[BACKUP] $JSF.bak_exportqa_v2_${TS}"

# ---- backend patch (param run_dir endpoints) ----
python3 - <<'PY'
from pathlib import Path
import re

pyf = Path("."+__import__("os").environ.get("PYF_PATH",""))
# fallback: locate again
root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
pyf = next(iter(root.rglob("vsp_demo_app.py")), None)
assert pyf, "vsp_demo_app.py not found"
s = pyf.read_text(encoding="utf-8", errors="replace")

MARK="VSP_EXPORT_QUICK_ACTIONS_P0_V2"
if MARK in s:
    print("[OK] backend v2 already present")
else:
    # ensure send_file import exists
    if "send_file" not in s:
        s = re.sub(r"from\s+flask\s+import\s+([^\n]+)",
                   lambda m: (m.group(0) if "send_file" in m.group(0) else m.group(0).rstrip()+", send_file"),
                   s, count=1)

    # ensure imports
    if "import subprocess" not in s:
        s = "import subprocess\nimport glob\nimport os\nimport json\n\n" + s

    inject = r'''
# ==== {MARK} ====
def _vsp_safe_run_dir__p0(run_dir: str) -> str:
    """allow only /home/test/Data/... directories to avoid path traversal"""
    if not run_dir:
        return ""
    run_dir = str(run_dir).strip()
    if "\x00" in run_dir:
        return ""
    if ".." in run_dir.replace("\\","/"):
        return ""
    if not run_dir.startswith("/home/test/Data/"):
        return ""
    if not os.path.isdir(run_dir):
        return ""
    return run_dir

def _vsp_pack_report__p0(run_dir: str):
    bundle = "/home/test/Data/SECURITY_BUNDLE"
    pack = f"{bundle}/bin/pack_report.sh"
    env = os.environ.copy()
    env["RUN_DIR"] = run_dir
    env["BUNDLE"] = bundle
    p = subprocess.run(["bash", pack], cwd=bundle, env=env, capture_output=True, text=True, timeout=240)
    tgzs = sorted(glob.glob(os.path.join(run_dir, "*__REPORT.tgz")), key=lambda x: os.path.getmtime(x), reverse=True)
    tgz = tgzs[0] if tgzs else ""
    sha = os.path.join(run_dir, "SHA256SUMS.txt")
    return {
        "ok": (p.returncode == 0 and bool(tgz)),
        "returncode": p.returncode,
        "stdout_tail": "\n".join((p.stdout or "").splitlines()[-60:]),
        "stderr_tail": "\n".join((p.stderr or "").splitlines()[-60:]),
        "tgz": tgz,
        "sha": sha if os.path.isfile(sha) else "",
        "run_dir": run_dir,
    }

@app.get("/api/vsp/export_report_tgz_v1")
def api_export_report_tgz_v1():
    try:
        run_dir = _vsp_safe_run_dir__p0(request.args.get("run_dir",""))
        if not run_dir:
            return jsonify({"ok": False, "error": "bad run_dir"}), 400
        res = _vsp_pack_report__p0(run_dir)
        if not res.get("ok"):
            return jsonify({"ok": False, "error": "pack failed", **res}), 500
        return send_file(res["tgz"], as_attachment=True, download_name=os.path.basename(res["tgz"]))
    except Exception as e:
        return jsonify({"ok": False, "error": "EXC", "msg": str(e)}), 500

@app.get("/api/vsp/open_report_html_v1")
def api_open_report_html_v1():
    try:
        run_dir = _vsp_safe_run_dir__p0(request.args.get("run_dir",""))
        if not run_dir:
            return "bad run_dir", 400
        html = os.path.join(run_dir, "report", "security_resilient.html")
        if not os.path.isfile(html):
            _vsp_pack_report__p0(run_dir)
        if not os.path.isfile(html):
            return "missing security_resilient.html", 404
        return send_file(html, mimetype="text/html")
    except Exception as e:
        return f"EXC: {e}", 500

@app.get("/api/vsp/verify_report_sha_v1")
def api_verify_report_sha_v1():
    try:
        run_dir = _vsp_safe_run_dir__p0(request.args.get("run_dir",""))
        if not run_dir:
            return jsonify({"ok": False, "error": "bad run_dir"}), 400
        _vsp_pack_report__p0(run_dir)
        sha = os.path.join(run_dir, "SHA256SUMS.txt")
        if not os.path.isfile(sha):
            return jsonify({"ok": False, "error": "missing SHA256SUMS.txt", "run_dir": run_dir}), 500
        p = subprocess.run(["bash","-lc", f'cd "{run_dir}" && sha256sum -c SHA256SUMS.txt'],
                           capture_output=True, text=True, timeout=30)
        return jsonify({
            "ok": (p.returncode == 0),
            "run_dir": run_dir,
            "returncode": p.returncode,
            "stdout": p.stdout,
            "stderr": p.stderr,
        }), (200 if p.returncode == 0 else 500)
    except Exception as e:
        return jsonify({"ok": False, "error": "EXC", "msg": str(e)}), 500
# ==== /{MARK} ====
'''.replace("{MARK}", MARK)

    m = re.search(r"\nif\s+__name__\s*==\s*[\"']__main__[\"']\s*:\n", s)
    if m:
        s = s[:m.start()] + "\n" + inject + "\n" + s[m.start():]
    else:
        s = s + "\n" + inject + "\n"

    pyf.write_text(s, encoding="utf-8")
    print("[OK] backend v2 injected:", MARK)
PY

# ---- JS patch: quick actions uses latest_rid_v1 client-side then calls *_v1?run_dir= ----
python3 - <<'PY'
from pathlib import Path
import re

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
jsf = next(iter(root.rglob("static/js/vsp_bundle_commercial_v2.js")), None)
assert jsf, "js bundle not found"
s = jsf.read_text(encoding="utf-8", errors="replace")

MARK="VSP_QUICK_ACTIONS_EXPORT_UI_P0_V2"
if MARK in s:
    print("[OK] JS v2 already present")
else:
    block = r'''
/* {MARK}: quick actions (client fetch latest_rid_v1 -> run_dir param endpoints) */
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
    setTimeout(function(){ try{t.remove();}catch(_){ } }, 2700);
  }

  css(`
    #vspQuickActions{ position:fixed; right:18px; bottom:18px; z-index:99999; width:300px;
      background:rgba(20,22,28,.92); border:1px solid rgba(255,255,255,.10);
      border-radius:16px; box-shadow:0 18px 45px rgba(0,0,0,.45);
      backdrop-filter: blur(10px); overflow:hidden; }
    #vspQuickActions .hd{ padding:12px 14px; display:flex; align-items:center; justify-content:space-between;
      border-bottom:1px solid rgba(255,255,255,.08); }
    #vspQuickActions .hd .t{ font-weight:800; font-size:12px; letter-spacing:.08em; opacity:.9; }
    #vspQuickActions .bd{ padding:12px 14px; display:grid; grid-template-columns:1fr; gap:10px; }
    #vspQuickActions button{ all:unset; cursor:pointer; padding:10px 12px; border-radius:12px;
      background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.10);
      display:flex; align-items:center; justify-content:space-between; font-weight:700; font-size:13px; }
    #vspQuickActions button:hover{ background:rgba(255,255,255,.10); }
    #vspQuickActions .muted{ opacity:.72; font-weight:650; font-size:12px; }
    #vspQuickActions .x{ cursor:pointer; opacity:.65; }
    #vspQuickActions .x:hover{ opacity:1; }
    #vspQuickActions .info{ opacity:.72; font-size:12px; line-height:1.2; }
    .vspToast{ position:fixed; right:22px; bottom:340px; z-index:100000; padding:10px 12px;
      background:rgba(22,24,30,.96); border:1px solid rgba(255,255,255,.10);
      border-radius:12px; transform:translateY(10px); opacity:0; transition:all .18s ease;
      box-shadow:0 14px 35px rgba(0,0,0,.45); font-size:13px; }
    .vspToast.on{ transform:translateY(0); opacity:1; }
    .vspToast.bad{ border-color: rgba(255,80,80,.35); }
  `);

  async function getRunDir(){
    var r = await fetch('/api/vsp/latest_rid_v1?ts=' + Date.now(), {cache:'no-store'});
    var j = await r.json();
    return { rid: j.rid || '', run_dir: j.ci_run_dir || '' };
  }

  function install(){
    if(document.getElementById('vspQuickActions')) return;

    var box=el('div','',null); box.id='vspQuickActions';
    var hd=el('div','hd',null);
    hd.appendChild(el('div','t','QUICK ACTIONS'));
    var close=el('div','x','✕'); close.title='Hide'; close.onclick=function(){ try{box.remove();}catch(_){ } };
    hd.appendChild(close);

    var bd=el('div','bd',null);
    var info=el('div','info','Export/Verify/Open report for <b>latest RID</b>.');
    bd.appendChild(info);

    var b1=el('button','', '<span>Export TGZ</span><span class="muted">download</span>');
    b1.onclick=async function(){
      try{
        toast('Resolving latest RID…');
        var x = await getRunDir();
        if(!x.run_dir){ toast('No ci_run_dir ❌', false); return; }
        toast('Packing & downloading…');
        window.location.href='/api/vsp/export_report_tgz_v1?run_dir='+encodeURIComponent(x.run_dir)+'&ts='+(Date.now());
      }catch(e){ toast('Export error ❌', false); }
    };

    var b2=el('button','', '<span>Open HTML report</span><span class="muted">new tab</span>');
    b2.onclick=async function(){
      try{
        toast('Resolving latest RID…');
        var x = await getRunDir();
        if(!x.run_dir){ toast('No ci_run_dir ❌', false); return; }
        window.open('/api/vsp/open_report_html_v1?run_dir='+encodeURIComponent(x.run_dir)+'&ts='+(Date.now()), '_blank');
      }catch(e){ toast('Open error ❌', false); }
    };

    var b3=el('button','', '<span>Verify SHA256</span><span class="muted">server</span>');
    b3.onclick=async function(){
      try{
        toast('Resolving latest RID…');
        var x = await getRunDir();
        if(!x.run_dir){ toast('No ci_run_dir ❌', false); return; }
        toast('Verifying…');
        var r=await fetch('/api/vsp/verify_report_sha_v1?run_dir='+encodeURIComponent(x.run_dir)+'&ts='+(Date.now()), {cache:'no-store'});
        var j=await r.json().catch(()=>({ok:false}));
        if(j.ok){ toast('SHA256 OK ✅', true); }
        else { toast('SHA256 FAIL ❌', false); }
      }catch(e){ toast('Verify error ❌', false); }
    };

    bd.appendChild(b1); bd.appendChild(b2); bd.appendChild(b3);
    box.appendChild(hd); box.appendChild(bd);
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
    print("[OK] appended JS v2:", MARK)
PY

echo "== checks =="
python3 -m py_compile "$PYF"
node --check "$JSF"

echo "== restart 8910 =="
if [ -x "$ROOT/bin/restart_ui_8910_hardreset_p0_v1.sh" ]; then
  bash "$ROOT/bin/restart_ui_8910_hardreset_p0_v1.sh"
else
  echo "[WARN] missing restart script, restart manually"
fi

echo "[NEXT] Ctrl+Shift+R. QUICK ACTIONS sẽ dùng endpoint *_v1?run_dir=... (ổn định hơn)."
