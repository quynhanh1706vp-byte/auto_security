#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
TPL="templates/vsp_runs_reports_v1.html"
MARK="VSP_RUNS_REPORTS_P0_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_fix_${MARK}_${TS}"
echo "[BACKUP] $APP.bak_fix_${MARK}_${TS}"

mkdir -p templates

# write template (safe overwrite)
cat > "$TPL" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>VSP Runs & Reports</title>
  <style>
    body{margin:0;background:#070d18;color:#dbe7ff;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial;}
    .top{position:sticky;top:0;z-index:9;background:#0b1220;border-bottom:1px solid rgba(255,255,255,.08)}
    .wrap{max-width:1400px;margin:0 auto;padding:12px 14px}
    a{color:#9fe2ff;text-decoration:none}
    .row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
    .pill{padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08)}
    input{background:#0b1220;color:#dbe7ff;border:1px solid rgba(255,255,255,.12);border-radius:10px;padding:8px 10px;min-width:320px;flex:1}
    table{width:100%;border-collapse:collapse;margin-top:12px}
    th,td{border-bottom:1px solid rgba(255,255,255,.08);padding:10px 8px;vertical-align:top}
    th{position:sticky;top:60px;background:#0b1220;text-align:left;font-size:12px;color:#9fb5de}
    .mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono",monospace}
    .small{font-size:12px}
    .muted{color:#8ea3c7}
    .btn{display:inline-block;padding:6px 9px;border-radius:10px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);margin-right:6px}
    .ok{color:#9be8a5}.bad{color:#ff6b6b}
  </style>
</head>
<body>
  <div class="top">
    <div class="wrap">
      <div class="row">
        <div style="font-weight:800;letter-spacing:.3px">VSP Runs & Reports</div>
        <div class="pill small muted">Source: /home/test/Data/SECURITY_BUNDLE/out</div>
        <div style="flex:1"></div>
        <a class="pill" href="/vsp4">Dashboard</a>
        <a class="pill" href="/data">Data Source</a>
        <a class="pill" href="/api/vsp/selfcheck_p0" target="_blank" rel="noopener">Selfcheck</a>
      </div>
      <div class="row" style="margin-top:10px">
        <input id="q" placeholder="Filter by run_id / name / date..."/>
        <div class="pill small muted" id="meta">loading…</div>
      </div>
    </div>
  </div>

  <div class="wrap">
    <table>
      <thead>
        <tr>
          <th style="width:340px">Run</th>
          <th style="width:150px">When</th>
          <th style="width:140px">Artifacts</th>
          <th>Quick open</th>
        </tr>
      </thead>
      <tbody id="tb"></tbody>
    </table>
  </div>

<script>
(async function(){
  const tb=document.getElementById('tb');
  const q=document.getElementById('q');
  const meta=document.getElementById('meta');

  function esc(s){ return (s??'').toString().replace(/[&<>"']/g, c=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }
  function norm(s){ return (s??'').toString().toLowerCase(); }

  const res = await fetch('/api/vsp/runs?limit=200');
  const data = await res.json();
  const items = data.items || [];

  function row(x){
    const rid = esc(x.run_id||'');
    const when = esc(x.mtime_h||'');
    const has = x.has || {};
    const tag = (b)=> b ? '<span class="ok">OK</span>' : '<span class="bad">—</span>';

    const links = [];
    if(has.summary) links.push(`<a class="btn mono" href="/api/vsp/run_file?run_id=${encodeURIComponent(rid)}&path=SUMMARY.txt" target="_blank">SUMMARY</a>`);
    if(has.json) links.push(`<a class="btn mono" href="/api/vsp/run_file?run_id=${encodeURIComponent(rid)}&path=findings_unified.json" target="_blank">JSON</a>`);
    if(has.csv) links.push(`<a class="btn mono" href="/api/vsp/run_file?run_id=${encodeURIComponent(rid)}&path=reports/findings_unified.csv" target="_blank">CSV</a>`);
    if(has.sarif) links.push(`<a class="btn mono" href="/api/vsp/run_file?run_id=${encodeURIComponent(rid)}&path=reports/findings_unified.sarif" target="_blank">SARIF</a>`);
    if(has.html) links.push(`<a class="btn" href="/api/vsp/run_file?run_id=${encodeURIComponent(rid)}&path=${encodeURIComponent(has.html_path)}" target="_blank">HTML</a>`);

    return `
      <tr>
        <td class="mono">
          <div style="font-weight:700">${rid}</div>
          <div class="small muted">${esc(x.path||'')}</div>
        </td>
        <td class="small">${when}</td>
        <td class="small mono">
          json:${tag(has.json)}<br/>
          csv:${tag(has.csv)}<br/>
          sarif:${tag(has.sarif)}<br/>
          summary:${tag(has.summary)}
        </td>
        <td>${links.join(' ') || '<span class="muted small">no artifacts</span>'}</td>
      </tr>
    `;
  }

  function render(){
    const qs = norm(q.value);
    const out = items.filter(x => !qs || norm([x.run_id,x.path,x.mtime_h].join(' ')).includes(qs));
    meta.textContent = `runs: ${out.length} / ${items.length}`;
    tb.innerHTML = out.map(row).join('');
  }

  q.addEventListener('input', render);
  render();
})();
</script>
</body>
</html>
HTML

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_RUNS_REPORTS_P0_V1"
app=Path("vsp_demo_app.py")
s=app.read_text(encoding="utf-8", errors="replace")

# remove any broken partial block if present
s = re.sub(r"\n?# === VSP_RUNS_REPORTS_P0_V1 ===.*?# === /VSP_RUNS_REPORTS_P0_V1 ===\n?", "\n", s, flags=re.S)

# ensure imports
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", s, flags=re.M)
need = ["render_template","jsonify","request","send_file"]
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

inject = r'''
# === VSP_RUNS_REPORTS_P0_V1 ===
from pathlib import Path as _VSP_Path
import time as _VSP_time

_VSP_OUT_ROOT = _VSP_Path("/home/test/Data/SECURITY_BUNDLE/out")

def _vsp_is_run_dir(p: _VSP_Path) -> bool:
    name = p.name
    if not p.is_dir():
        return False
    return ("_RUN_" in name) or name.startswith("RUN_")

def _vsp_pick_html_report(run_dir: _VSP_Path):
    cands = [
        run_dir / "report" / "index.html",
        run_dir / "reports" / "index.html",
        run_dir / "reports" / "findings_unified.html",
        run_dir / "report.html",
    ]
    for fp in cands:
        if fp.exists():
            try:
                return str(fp.relative_to(run_dir))
            except Exception:
                return None
    for sub in ("report","reports"):
        d = run_dir / sub
        if d.exists():
            for fp in sorted(d.rglob("*.html"))[:1]:
                try:
                    return str(fp.relative_to(run_dir))
                except Exception:
                    pass
    return None

def _vsp_has(run_dir: _VSP_Path):
    has = {}
    has["summary"] = (run_dir/"SUMMARY.txt").exists()
    has["json"] = (run_dir/"findings_unified.json").exists()
    has["csv"] = (run_dir/"reports"/"findings_unified.csv").exists()
    has["sarif"] = (run_dir/"reports"/"findings_unified.sarif").exists()
    htmlp = _vsp_pick_html_report(run_dir)
    has["html"] = bool(htmlp)
    has["html_path"] = htmlp
    return has

@app.get("/runs")
def vsp_runs_page():
    return render_template("vsp_runs_reports_v1.html")

@app.get("/api/vsp/runs")
def vsp_api_runs():
    from flask import request
    try:
        limit = int(request.args.get("limit","100"))
    except Exception:
        limit = 100
    items=[]
    root=_VSP_OUT_ROOT
    if root.exists():
        for p in root.iterdir():
            if not _vsp_is_run_dir(p):
                continue
            st = p.stat()
            mtime = int(st.st_mtime)
            items.append({
                "run_id": p.name,
                "path": str(p),
                "mtime": mtime,
                "mtime_h": _VSP_time.strftime("%Y-%m-%d %H:%M:%S", _VSP_time.localtime(mtime)),
                "has": _vsp_has(p),
            })
    items.sort(key=lambda x: x.get("mtime",0), reverse=True)
    items = items[:max(1, min(limit, 1000))]
    return jsonify({"ok": True, "who": "VSP_RUNS_REPORTS_P0_V1", "root": str(root), "items": items, "items_len": len(items)})

@app.get("/api/vsp/run_file")
def vsp_api_run_file():
    from flask import request, send_file, jsonify
    run_id = request.args.get("run_id","")
    rel = request.args.get("path","")
    if not run_id or not rel:
        return jsonify({"ok": False, "error":"MISSING_PARAMS"}), 400
    rd = _VSP_OUT_ROOT / run_id
    if not rd.exists():
        return jsonify({"ok": False, "error":"NO_SUCH_RUN"}), 404
    rp = (rd / rel).resolve()
    if str(rp).find(str(rd.resolve())) != 0:
        return jsonify({"ok": False, "error":"PATH_TRAVERSAL"}), 400
    if not rp.exists() or not rp.is_file():
        return jsonify({"ok": False, "error":"NO_FILE"}), 404
    return send_file(str(rp))
# === /VSP_RUNS_REPORTS_P0_V1 ===
'''.strip()

s = s + "\n\n" + inject + "\n"
app.write_text(s, encoding="utf-8")
print("[OK] injected clean Runs & Reports block")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 then:"
echo "  curl -sS 'http://127.0.0.1:8910/api/vsp/runs?limit=5' | jq .ok,.items_len,.root -C"
echo "  open http://127.0.0.1:8910/runs"
