#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
MOD="vsp_runs_reports_bp.py"
TPL="templates/vsp_runs_reports_v1.html"
MARK="VSP_RUNS_REPORTS_BP_SAFE_P0_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_${MARK}_${TS}"
echo "[BACKUP] $APP.bak_${MARK}_${TS}"

mkdir -p templates

# (1) template (overwrite OK)
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

# (2) blueprint module (overwrite OK)
cat > "$MOD" <<'PY'
from __future__ import annotations
from pathlib import Path
import time
from flask import Blueprint, jsonify, request, render_template, send_file

MARK = "VSP_RUNS_REPORTS_BP_SAFE_P0_V1"
OUT_ROOT = Path("/home/test/Data/SECURITY_BUNDLE/out").resolve()

bp = Blueprint("vsp_runs_reports_bp", __name__)

def _is_run_dir(p: Path) -> bool:
    if not p.is_dir():
        return False
    name = p.name
    return ("_RUN_" in name) or name.startswith("RUN_") or name.startswith("CODE_") or name.endswith("_RUN")

def _pick_html_report(run_dir: Path):
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

def _has(run_dir: Path):
    htmlp = _pick_html_report(run_dir)
    return {
        "summary": (run_dir/"SUMMARY.txt").exists(),
        "json": (run_dir/"findings_unified.json").exists(),
        "csv": (run_dir/"reports"/"findings_unified.csv").exists(),
        "sarif": (run_dir/"reports"/"findings_unified.sarif").exists(),
        "html": bool(htmlp),
        "html_path": htmlp,
    }

@bp.get("/runs")
def runs_page():
    return render_template("vsp_runs_reports_v1.html")

@bp.get("/api/vsp/runs")
def api_runs():
    try:
        limit = int(request.args.get("limit","100"))
    except Exception:
        limit = 100
    limit = max(1, min(limit, 1000))

    items = []
    if OUT_ROOT.exists():
        for p in OUT_ROOT.iterdir():
            if not _is_run_dir(p):
                continue
            try:
                st = p.stat()
                mtime = int(st.st_mtime)
            except Exception:
                mtime = 0
            items.append({
                "run_id": p.name,
                "path": str(p),
                "mtime": mtime,
                "mtime_h": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime)) if mtime else "n/a",
                "has": _has(p),
            })

    items.sort(key=lambda x: x.get("mtime",0), reverse=True)
    items = items[:limit]
    return jsonify({"ok": True, "who": MARK, "root": str(OUT_ROOT), "items": items, "items_len": len(items)})

@bp.get("/api/vsp/run_file")
def api_run_file():
    run_id = (request.args.get("run_id","") or "").strip()
    rel = (request.args.get("path","") or "").strip()
    if not run_id or not rel:
        return jsonify({"ok": False, "error": "MISSING_PARAMS"}), 400

    rd = (OUT_ROOT / run_id).resolve()
    if not rd.exists():
        return jsonify({"ok": False, "error": "NO_SUCH_RUN"}), 404

    rp = (rd / rel).resolve()
    if str(rp).find(str(rd)) != 0:
        return jsonify({"ok": False, "error": "PATH_TRAVERSAL"}), 400
    if (not rp.exists()) or (not rp.is_file()):
        return jsonify({"ok": False, "error": "NO_FILE"}), 404

    return send_file(str(rp))
PY

# (3) patch vsp_demo_app.py: just register bp (very small)
python3 - <<'PY'
from pathlib import Path
import re

APP=Path("vsp_demo_app.py")
s=APP.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUNS_REPORTS_BP_SAFE_P0_V1"

if MARK in s:
    print("[OK] already registered:", MARK)
else:
    block = r'''
# === VSP_RUNS_REPORTS_BP_SAFE_P0_V1 ===
try:
    from vsp_runs_reports_bp import bp as vsp_runs_reports_bp
    app.register_blueprint(vsp_runs_reports_bp)
    print("[VSP_RUNS_REPORTS_BP] mounted /runs + /api/vsp/runs + /api/vsp/run_file")
except Exception as _e:
    try:
        print("[VSP_RUNS_REPORTS_BP][WARN] not mounted:", _e)
    except Exception:
        pass
# === /VSP_RUNS_REPORTS_BP_SAFE_P0_V1 ===
'''.strip() + "\n"

    # insert BEFORE if __name__ == "__main__" if exists, else append
    m = re.search(r'^\s*if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*$', s, flags=re.M)
    if m:
        s = s[:m.start()] + block + "\n" + s[m.start():]
    else:
        s = s + "\n\n" + block

    APP.write_text(s, encoding="utf-8")
    print("[OK] injected register block:", MARK)

# sanity: ensure Blueprint symbol is available (your earlier crash)
# If flask import line exists but lacks Blueprint, add it.
s=APP.read_text(encoding="utf-8", errors="replace")
m = re.search(r'^from\s+flask\s+import\s+([^\n]+)$', s, flags=re.M)
if m:
    items=[x.strip() for x in m.group(1).split(",")]
    if "Blueprint" not in items:
        items.append("Blueprint")
        s = s[:m.start()] + "from flask import " + ", ".join(items) + s[m.end():]
        APP.write_text(s, encoding="utf-8")
        print("[OK] ensured Blueprint in flask import")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "[NEXT] restart 8910 then verify:"
echo "  curl -sS 'http://127.0.0.1:8910/api/vsp/runs?limit=3' | jq .ok,.items_len,.who -C"
echo "  open http://127.0.0.1:8910/runs"
