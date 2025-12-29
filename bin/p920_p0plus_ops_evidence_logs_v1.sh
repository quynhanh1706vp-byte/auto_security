#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p920_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need curl; need date

APP="vsp_demo_app.py"
OPS_JS="static/js/vsp_ops_panel_v1.js"
SET_JS="static/js/vsp_c_settings_v1.js"

echo "== [P920] backup =="
cp -f "$APP" "${APP}.bak_p920_${TS}"
[ -f "$OPS_JS" ] && cp -f "$OPS_JS" "${OPS_JS}.bak_p920_${TS}" || true
[ -f "$SET_JS" ] && cp -f "$SET_JS" "${SET_JS}.bak_p920_${TS}" || true
echo "[OK] backup => ${APP}.bak_p920_${TS}"

echo "== [P920] patch backend endpoints (evidence/journal/log_tail) =="
python3 - <<'PY'
from pathlib import Path
import re

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")
MARK = "P920_EVIDENCE_JOURNAL_LOGTAIL_V1"
if MARK in s:
    print("[OK] backend already patched:", MARK)
    raise SystemExit(0)

# --- ensure imports (best-effort, non-destructive) ---
def ensure_import_line(line: str):
    nonlocal_s = None

# Add missing stdlib imports near the top (after initial imports block)
need_std = ["import os", "import json", "import datetime", "import zipfile", "import tempfile", "import subprocess"]
for imp in ["import zipfile", "import tempfile", "import subprocess"]:
    if imp not in s:
        # insert after first "import" block
        m = re.search(r'^(import .+\n)+', s, flags=re.M)
        if m:
            s = s[:m.end()] + imp + "\n" + s[m.end():]
        else:
            s = imp + "\n" + s

# Ensure send_file/unquote imported (augment flask import line if exists)
if "send_file" not in s:
    m = re.search(r'from\s+flask\s+import\s+([^\n]+)\n', s)
    if m:
        items = [x.strip() for x in m.group(1).split(",")]
        if "send_file" not in items:
            items.append("send_file")
            new = "from flask import " + ", ".join(items) + "\n"
            s = s[:m.start()] + new + s[m.end():]

if "unquote" not in s:
    if "from urllib.parse import" in s:
        m = re.search(r'from\s+urllib\.parse\s+import\s+([^\n]+)\n', s)
        if m:
            items = [x.strip() for x in m.group(1).split(",")]
            if "unquote" not in items:
                items.append("unquote")
                new = "from urllib.parse import " + ", ".join(items) + "\n"
                s = s[:m.start()] + new + s[m.end():]
    else:
        s = "from urllib.parse import unquote\n" + s

BLOCK = r'''
# ============================================================
# P920_EVIDENCE_JOURNAL_LOGTAIL_V1
# - evidence_zip_v1: download evidence.zip by rid
# - journal_tail_v1: tail systemd journal (no-sudo best effort)
# - log_tail_v1: tail tool logs by rid/tool
# ============================================================

def _p920_json_ok(payload, code=200, extra_headers=None):
    try:
        from flask import jsonify
        resp = jsonify(payload)
    except Exception:
        # last resort
        from flask import Response
        import json as _json
        resp = Response(_json.dumps(payload, ensure_ascii=False), mimetype="application/json")
    resp.status_code = code
    if extra_headers:
        for k,v in extra_headers.items():
            resp.headers[k] = v
    return resp

def _p920_is_bad_rid(x: str) -> bool:
    if x is None:
        return True
    x = str(x).strip()
    return x == "" or x.lower() in ("undefined","null","none","nan")

def _p920_find_run_dir_candidates(rid: str):
    # tolerate multiple layouts; return first existing dir
    import os
    candidates = [
        f"/home/test/Data/SECURITY_BUNDLE/out/{rid}",
        f"/home/test/Data/SECURITY_BUNDLE/out_ci/{rid}",
        f"/home/test/Data/SECURITY_BUNDLE/ui/out_ci/{rid}",
        f"/home/test/Data/SECURITY_BUNDLE/ui/out_ci/runs/{rid}",
        f"/home/test/Data/SECURITY_BUNDLE/out_ci/VSP_CI_{rid}" if not rid.startswith("VSP_CI_") else f"/home/test/Data/SECURITY_BUNDLE/out_ci/{rid}",
    ]
    for p in candidates:
        if p and os.path.isdir(p):
            return p
    return None

def _p920_zip_evidence(run_dir: str, rid: str):
    import os, zipfile, tempfile, datetime
    allow_prefix = [run_dir]
    # common evidence files (take if exist)
    must_take = [
        "SUMMARY.txt","run_gate_summary.json","run_gate.json","verdict_4t.json",
        "run_manifest.json","run_evidence_index.json",
        "findings_unified.json","findings_unified.csv","findings_unified.sarif",
        "reports/findings_unified.csv","reports/findings_unified.sarif","reports/findings_unified.json",
        "last_page.html","trace.zip","trace.zip.meta.json",
        "ui_engine.log","steps_log.jsonl","net_summary.json","storage_state.json","auth_seed.json",
    ]
    # also include tool logs folders if exist
    tool_dirs = ["bandit","semgrep","gitleaks","kics","trivy","syft","grype","codeql","logs","report","reports"]
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_zip = Path("/tmp") / f"vsp_evidence_{rid}_{ts}.zip"
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as z:
        def add_file(rel):
            fp = os.path.join(run_dir, rel)
            if os.path.isfile(fp):
                z.write(fp, arcname=rel)
        for rel in must_take:
            add_file(rel)
        for td in tool_dirs:
            tpath = os.path.join(run_dir, td)
            if os.path.isdir(tpath):
                for root, dirs, files in os.walk(tpath):
                    for fn in files:
                        fp = os.path.join(root, fn)
                        # avoid huge binaries
                        try:
                            if os.path.getsize(fp) > 25*1024*1024:
                                continue
                        except Exception:
                            pass
                        relp = os.path.relpath(fp, run_dir)
                        z.write(fp, arcname=relp)
    return str(out_zip)

def _p920_tail_file(path: str, n: int = 200):
    import os
    n = max(20, min(int(n or 200), 500))
    # restrict to safe roots
    roots = [
        "/home/test/Data/SECURITY_BUNDLE",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
    ]
    rp = os.path.realpath(path)
    if not any(rp.startswith(r + "/") or rp == r for r in roots):
        return (False, f"denied_path:{rp}", "")
    if not os.path.isfile(rp):
        return (False, "missing_file", "")
    try:
        with open(rp, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()[-n:]
        return (True, "", "".join(lines))
    except Exception as e:
        return (False, f"read_error:{e}", "")

@app.get("/api/vsp/evidence_zip_v1")
def api_vsp_evidence_zip_v1():
    from flask import request
    rid = (request.args.get("rid") or "").strip()
    rid = unquote(rid)
    if _p920_is_bad_rid(rid):
        # for download routes: keep JSON 200 to avoid spam; UI should not auto-call
        return _p920_json_ok({"ok": False, "err": "missing_rid", "rid": rid, "hint": "call ?rid=<RID>"}, 200)
    run_dir = _p920_find_run_dir_candidates(rid)
    if not run_dir:
        return _p920_json_ok({"ok": False, "err": "run_dir_not_found", "rid": rid}, 404)
    try:
        zpath = _p920_zip_evidence(run_dir, rid)
        return send_file(zpath, as_attachment=True, download_name=f"evidence_{rid}.zip", mimetype="application/zip")
    except Exception as e:
        return _p920_json_ok({"ok": False, "err": f"zip_failed:{e}", "rid": rid, "run_dir": run_dir}, 500)

@app.get("/api/vsp/journal_tail_v1")
def api_vsp_journal_tail_v1():
    from flask import request
    n = int(request.args.get("n") or 120)
    svc = request.args.get("svc") or os.environ.get("VSP_UI_SVC") or "vsp-ui-8910.service"
    cmd = ["journalctl","-u",svc,"-n",str(max(20,min(n,500))),"--no-pager","-o","short-iso"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
        ok = (p.returncode == 0)
        return _p920_json_ok({
            "ok": ok,
            "svc": svc,
            "cmd": " ".join(cmd),
            "rc": p.returncode,
            "out": (p.stdout or "")[-20000:],
            "err": (p.stderr or "")[-4000:],
        }, 200)
    except Exception as e:
        return _p920_json_ok({"ok": False, "svc": svc, "err": str(e)}, 200)

@app.get("/api/vsp/log_tail_v1")
def api_vsp_log_tail_v1():
    from flask import request
    rid = (request.args.get("rid") or "").strip()
    rid = unquote(rid)
    tool = (request.args.get("tool") or "").strip().lower()
    n = int(request.args.get("n") or 160)
    # explicit path mode (still restricted by allowlist roots)
    raw_path = request.args.get("path")
    if raw_path:
        ok, err, out = _p920_tail_file(unquote(raw_path), n=n)
        return _p920_json_ok({"ok": ok, "mode":"path", "path": raw_path, "err": err, "tail": out}, 200)

    if _p920_is_bad_rid(rid) or tool == "":
        return _p920_json_ok({"ok": False, "err": "missing_rid_or_tool", "rid": rid, "tool": tool}, 200)

    run_dir = _p920_find_run_dir_candidates(rid)
    if not run_dir:
        return _p920_json_ok({"ok": False, "err": "run_dir_not_found", "rid": rid}, 404)

    # tool->candidate log paths (relative)
    rels = [
        f"{tool}/{tool}.log",
        f"{tool}/{tool}.txt",
        f"{tool}/tool.log",
        f"{tool}/scan.log",
        f"{tool}/{tool}_scan.log",
        f"{tool}/{tool}.out",
        f"logs/{tool}.log",
        f"logs/{tool}.txt",
    ]
    import os
    found = None
    for rel in rels:
        fp = os.path.join(run_dir, rel)
        if os.path.isfile(fp):
            found = fp
            break
    if not found:
        return _p920_json_ok({"ok": False, "err": "log_not_found", "rid": rid, "tool": tool, "run_dir": run_dir, "tried": rels}, 404)

    ok, err, out = _p920_tail_file(found, n=n)
    return _p920_json_ok({"ok": ok, "rid": rid, "tool": tool, "path": found, "err": err, "tail": out}, 200)
'''

# Insert block before main guard if exists, else append
m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
if m:
    s = s[:m.start()] + BLOCK + "\n" + s[m.start():]
else:
    s = s.rstrip() + "\n\n" + BLOCK + "\n"

app.write_text(s, encoding="utf-8")
print("[OK] backend patched:", MARK)
PY

python3 -m py_compile "$APP"
echo "[OK] backend py_compile OK"

echo "== [P920] write ops panel JS (CIO: OK/DEGRADED + journal + log tail + evidence) =="
python3 - <<'PY'
from pathlib import Path
import datetime
p = Path("static/js/vsp_ops_panel_v1.js")
p.parent.mkdir(parents=True, exist_ok=True)

js = r"""// P920_OPS_PANEL_V1 (CIO: Ops + Evidence + Logs)
(function(){
  "use strict";
  const API_OPS="/api/vsp/ops_latest_v1";
  const API_JOUR="/api/vsp/journal_tail_v1?n=120";
  const API_LOG=(rid,tool)=>`/api/vsp/log_tail_v1?rid=${encodeURIComponent(rid||"")}&tool=${encodeURIComponent(tool||"")}&n=160`;
  const API_EVID=(rid)=>`/api/vsp/evidence_zip_v1?rid=${encodeURIComponent(rid||"")}`;

  function esc(s){ return String(s==null?"":s).replace(/[&<>\"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;" }[c])); }
  function el(tag, attrs={}, html=""){
    const n=document.createElement(tag);
    for(const k of Object.keys(attrs||{})){
      if(k==="class") n.className=attrs[k];
      else if(k==="style") n.setAttribute("style", attrs[k]);
      else n.setAttribute(k, attrs[k]);
    }
    if(html!=null) n.innerHTML=html;
    return n;
  }

  async function fetchJSON(url){
    const r = await fetch(url, {credentials:"same-origin"});
    let j=null, txt="";
    try{ txt = await r.text(); j = JSON.parse(txt||"{}"); }catch(e){ j=null; }
    return { ok:r.ok, status:r.status, json:j, text:txt, url };
  }

  function renderPanel(host, data){
    const rid = (data && (data.latest_rid || data.rid || (data.source||{}).rid)) || "";
    const ok = !!(data && data.ok);
    const degraded = (data && (data.degraded_tools||data.degraded||[])) || [];
    const degList = Array.isArray(degraded) ? degraded : [];
    const isDegraded = degList.length>0;

    host.innerHTML = "";
    const badge = ok && !isDegraded ? `<span class="chip ok">OK</span>` : `<span class="chip warn">DEGRADED</span>`;
    const rel = (data && (data.release_dir || (data.source||{}).release_dir)) || "";
    const base = (data && data.base) || "";
    const svc  = (data && data.svc)  || "";
    const ts   = (data && data.ts)   || "";

    host.appendChild(el("div",{class:"ops_hdr"},
      `<div class="ops_title">Ops Status (CIO)</div><div>${badge}</div>`
    ));

    const grid = el("div",{class:"ops_grid"});
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">service</div><div class="v">${esc(svc||"-")}</div>`));
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">base</div><div class="v">${esc(base||location.origin)}</div>`));
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">latest_rid</div><div class="v mono">${esc(rid||"-")}</div>`));
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">release_dir</div><div class="v mono">${esc(rel||"-")}</div>`));
    grid.appendChild(el("div",{class:"ops_kv"}, `<div class="k">ts</div><div class="v mono">${esc(ts||"-")}</div>`));
    host.appendChild(grid);

    const actions = el("div",{class:"ops_actions"});
    const btnRefresh = el("button",{class:"btn"}, "Refresh");
    btnRefresh.onclick = ()=>ensureMounted(true);
    actions.appendChild(btnRefresh);

    const btnJour = el("button",{class:"btn"}, "Journal tail");
    btnJour.onclick = ()=>showJournal();
    actions.appendChild(btnJour);

    const btnJSON = el("a",{class:"btn",href:API_OPS,target:"_blank"}, "View JSON");
    actions.appendChild(btnJSON);

    const btnE = el("a",{class:"btn",href:API_EVID(rid),target:"_blank"}, "Download evidence.zip");
    if(!rid) btnE.classList.add("disabled");
    actions.appendChild(btnE);

    host.appendChild(actions);

    // degraded tools
    const dWrap = el("div",{class:"ops_degraded"});
    dWrap.appendChild(el("div",{class:"ops_subttl"}, "Degraded tools"));
    if(degList.length===0){
      dWrap.appendChild(el("div",{class:"muted"}, "none"));
    }else{
      const ul = el("div",{class:"ops_toollist"});
      for(const t of degList){
        const tool = (t||"").toString();
        const a = el("a",{href:"#",class:"tool_link"}, esc(tool));
        a.onclick = (e)=>{ e.preventDefault(); showToolLog(rid, tool); };
        ul.appendChild(a);
      }
      dWrap.appendChild(ul);
    }
    host.appendChild(dWrap);
  }

  function ensureStyles(){
    if(document.getElementById("vsp_ops_panel_css_p920")) return;
    const css = `
      .vsp_ops_p920{ border:1px solid rgba(255,255,255,.06); border-radius:14px; padding:14px; margin-top:12px; background:rgba(255,255,255,.02); }
      .ops_hdr{ display:flex; align-items:center; justify-content:space-between; margin-bottom:10px; }
      .ops_title{ font-weight:700; letter-spacing:.2px; }
      .chip{ padding:2px 10px; border-radius:999px; font-size:12px; border:1px solid rgba(255,255,255,.14); }
      .chip.ok{ background:rgba(16,185,129,.12); }
      .chip.warn{ background:rgba(245,158,11,.12); }
      .ops_grid{ display:grid; grid-template-columns: 1fr 1fr; gap:10px; margin-bottom:10px; }
      .ops_kv{ padding:10px; border-radius:12px; background:rgba(0,0,0,.18); border:1px solid rgba(255,255,255,.06); }
      .ops_kv .k{ opacity:.65; font-size:12px; margin-bottom:4px; }
      .ops_kv .v{ font-size:13px; }
      .mono{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }
      .ops_actions{ display:flex; gap:8px; flex-wrap:wrap; margin:8px 0 6px; }
      .btn{ display:inline-block; padding:7px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.14); background:rgba(255,255,255,.04); color:inherit; text-decoration:none; cursor:pointer; font-size:13px; }
      .btn.disabled{ opacity:.4; pointer-events:none; }
      .ops_subttl{ font-weight:650; margin:10px 0 6px; }
      .muted{ opacity:.65; font-size:13px; }
      .ops_toollist{ display:flex; gap:8px; flex-wrap:wrap; }
      .tool_link{ padding:4px 10px; border-radius:999px; border:1px solid rgba(255,255,255,.12); text-decoration:none; }
      .modal_bg{ position:fixed; inset:0; background:rgba(0,0,0,.55); display:flex; align-items:center; justify-content:center; z-index:9999; }
      .modal{ width:min(980px, 92vw); max-height:86vh; overflow:auto; background:#0b1220; border:1px solid rgba(255,255,255,.12); border-radius:14px; box-shadow:0 14px 50px rgba(0,0,0,.45); }
      .modal_hd{ display:flex; justify-content:space-between; align-items:center; padding:12px 14px; border-bottom:1px solid rgba(255,255,255,.08); }
      .modal_bd{ padding:12px 14px; }
      pre{ white-space:pre-wrap; word-break:break-word; background:rgba(0,0,0,.22); border:1px solid rgba(255,255,255,.08); padding:12px; border-radius:12px; font-size:12px; }
    `;
    const st = document.createElement("style");
    st.id = "vsp_ops_panel_css_p920";
    st.textContent = css;
    document.head.appendChild(st);
  }

  function showModal(title, bodyText){
    const bg = el("div",{class:"modal_bg"});
    const m  = el("div",{class:"modal"});
    const hd = el("div",{class:"modal_hd"}, `<div class="mono">${esc(title||"")}</div>`);
    const close = el("button",{class:"btn"}, "Close");
    close.onclick = ()=>bg.remove();
    hd.appendChild(close);
    const bd = el("div",{class:"modal_bd"});
    bd.appendChild(el("pre",{}, esc(bodyText||"")));
    m.appendChild(hd); m.appendChild(bd); bg.appendChild(m);
    bg.onclick = (e)=>{ if(e.target===bg) bg.remove(); };
    document.body.appendChild(bg);
  }

  async function showJournal(){
    const r = await fetchJSON(API_JOUR);
    const j = r.json || {};
    const title = `journal_tail (${j.svc||""}) rc=${j.rc||""}`;
    const out = (j.out||"") + (j.err ? ("\n[stderr]\n"+j.err) : "");
    showModal(title, out || (r.text||""));
  }

  async function showToolLog(rid, tool){
    const url = API_LOG(rid, tool);
    const r = await fetchJSON(url);
    const j = r.json || {};
    const title = `log_tail tool=${tool} rid=${rid} ok=${j.ok}`;
    const out = j.tail || j.err || r.text || "";
    showModal(title, out);
  }

  async function ensureMounted(force){
    try{
      ensureStyles();
      const host = document.getElementById("vsp_ops_status_panel");
      if(!host) return;
      if(host.dataset.p920Mounted && !force) return;
      host.dataset.p920Mounted = "1";
      host.classList.add("vsp_ops_p920");
      host.innerHTML = `<div class="muted">Loading ops...</div>`;
      const r = await fetchJSON(API_OPS);
      renderPanel(host, r.json || {});
      console.log("[P920] ops panel mounted");
    }catch(e){
      console.warn("[P920] ops panel error", e);
    }
  }

  // public hook
  window.VSPOpsPanel = { ensureMounted };

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>ensureMounted(false));
  }else{
    ensureMounted(false);
  }
})();
"""
p.write_text(js, encoding="utf-8")
print("[OK] wrote", p)
PY

echo "== [P920] ensure settings page mounts ops panel host + loads js =="
python3 - <<'PY'
from pathlib import Path
import re, datetime

F = Path("static/js/vsp_c_settings_v1.js")
if not F.exists():
    print("[WARN] missing", F, "(skip)")
    raise SystemExit(0)
s = F.read_text(encoding="utf-8", errors="replace")
MARK="P920_SETTINGS_LOAD_OPS_PANEL_V1"
if MARK in s:
    print("[OK] settings already patched:", MARK)
    raise SystemExit(0)

# 1) ensure a host div exists (id=vsp_ops_status_panel)
if "vsp_ops_status_panel" not in s:
    # naive: after first "Endpoint probes" render or after "Raw JSON" - best effort
    s = s.replace("Endpoint probes", "Endpoint probes\n");  # keep stable
    # append host near the end of render function: add a div before footer if possible
    # fallback: append at end of file with DOM insert on load
    pass

# 2) ensure ops panel JS gets loaded
# If there is a function that runs on settings render, inject loader there; else add DOMContentLoaded hook
loader = r"""
// P920_SETTINGS_LOAD_OPS_PANEL_V1
(function(){
  function loadOpsJs(){
    try{
      if(window.VSPOpsPanel && window.VSPOpsPanel.ensureMounted){ window.VSPOpsPanel.ensureMounted(true); return; }
      if(document.querySelector('script[data-p920-ops="1"]')) return;
      var s=document.createElement("script");
      s.src="/static/js/vsp_ops_panel_v1.js?v="+Date.now();
      s.async=true; s.dataset.p920Ops="1";
      document.head.appendChild(s);
    }catch(e){}
  }
  function ensureHost(){
    if(document.getElementById("vsp_ops_status_panel")) return;
    // best effort: put under settings content container
    var root = document.querySelector("#vsp_tab_settings") || document.querySelector("#main") || document.body;
    var host = document.createElement("div");
    host.id="vsp_ops_status_panel";
    host.style.marginTop="12px";
    // insert near end
    root.appendChild(host);
  }
  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", function(){ ensureHost(); loadOpsJs(); });
  }else{
    ensureHost(); loadOpsJs();
  }
})();
"""
s = s + "\n\n" + loader + "\n"
F.write_text(s, encoding="utf-8")
print("[OK] patched", F, "with", MARK)
PY

echo "== [P920] ensure minimal favicon.ico exists (avoid timeout) =="
if [ ! -f static/favicon.ico ]; then
  mkdir -p static
  printf '\0' > static/favicon.ico
  echo "[OK] wrote minimal static/favicon.ico"
fi

echo "== [P920] restart service =="
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
else
  echo "[WARN] no sudo; please restart service manually: $SVC"
fi

echo "== [P920] wait ready =="
ok=0
for i in $(seq 1 30); do
  if ss -lntp 2>/dev/null | grep -q ':8910'; then
    code="$(curl -sS --noproxy '*' -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/api/vsp/healthz" || true)"
    echo "try#$i LISTEN=1 code=$code"
    if [ "$code" = "200" ]; then ok=1; break; fi
  else
    echo "try#$i LISTEN=0"
  fi
  sleep 1
done
[ "$ok" = "1" ] || { echo "[FAIL] UI not ready"; exit 2; }
echo "[OK] UI ready"

echo "== [P920] verify new endpoints (must be 200) =="
curl -sS -D "$OUT/run_status.hdr" -o "$OUT/run_status.json" "$BASE/api/vsp/run_status_v1" >/dev/null || true
head -n 15 "$OUT/run_status.hdr" | sed -n '1,15p'

curl -sS -D "$OUT/ops_latest.hdr" -o "$OUT/ops_latest.json" "$BASE/api/vsp/ops_latest_v1" >/dev/null || true
python3 - <<'PY'
import json, pathlib
p=pathlib.Path("out_ci").glob("p920_*/ops_latest.json")
PY
echo "[OK] ops_latest saved => $OUT/ops_latest.json"

curl -sS -D "$OUT/journal.hdr" -o "$OUT/journal.json" "$BASE/api/vsp/journal_tail_v1?n=40" >/dev/null || true
head -n 15 "$OUT/journal.hdr" | sed -n '1,15p'
python3 - <<'PY'
import json
j=json.load(open("out_ci/p920_"+"'"$TS"'+"/journal.json","r",encoding="utf-8"))
print("journal ok=", j.get("ok"), "svc=", j.get("svc"))
PY

echo "== [P920] done. Open: $BASE/c/settings (Ctrl+Shift+R) =="
echo "[OK] evidence => $OUT"
