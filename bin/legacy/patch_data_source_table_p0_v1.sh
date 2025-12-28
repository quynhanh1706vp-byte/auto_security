#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
TPL="templates/vsp_data_source_v1.html"
MARK="VSP_DATA_SOURCE_P0_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_${MARK}_${TS}"
echo "[BACKUP] $APP.bak_${MARK}_${TS}"

mkdir -p templates static/js

# 1) write template
cat > "$TPL" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>VSP Data Source</title>
  <style>
    body{margin:0;background:#070d18;color:#dbe7ff;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial;}
    .top{position:sticky;top:0;z-index:9;background:#0b1220;border-bottom:1px solid rgba(255,255,255,.08)}
    .wrap{max-width:1400px;margin:0 auto;padding:12px 14px}
    a{color:#9fe2ff;text-decoration:none}
    .row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
    .pill{padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08)}
    input,select{background:#0b1220;color:#dbe7ff;border:1px solid rgba(255,255,255,.12);border-radius:10px;padding:8px 10px}
    table{width:100%;border-collapse:collapse;margin-top:12px}
    th,td{border-bottom:1px solid rgba(255,255,255,.08);padding:10px 8px;vertical-align:top}
    th{position:sticky;top:74px;background:#0b1220;text-align:left;font-size:12px;color:#9fb5de}
    .sev{font-weight:700}
    .sev.CRITICAL{color:#ff6b6b}.sev.HIGH{color:#ffb86b}.sev.MEDIUM{color:#ffd36b}.sev.LOW{color:#9be8a5}.sev.INFO{color:#9fe2ff}.sev.TRACE{color:#a8b3c7}
    .muted{color:#8ea3c7}
    .mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono",monospace}
    .small{font-size:12px}
  </style>
</head>
<body>
  <div class="top">
    <div class="wrap">
      <div class="row">
        <div style="font-weight:800;letter-spacing:.3px">VSP Data Source</div>
        <div class="pill small muted">Drilldown from findings_unified.json</div>
        <div style="flex:1"></div>
        <a class="pill" href="/vsp4">Dashboard</a>
        <a class="pill" href="/vsp5">5-Tabs</a>
        <a class="pill" href="/api/vsp/selfcheck_p0" target="_blank" rel="noopener">Selfcheck</a>
      </div>
      <div class="row" style="margin-top:10px">
        <input id="q" placeholder="Search (title/path/cwe/rule/tool)..." style="min-width:320px;flex:1"/>
        <select id="sev"><option value="">All severity</option></select>
        <select id="tool"><option value="">All tools</option></select>
        <div class="pill small muted" id="meta">loading…</div>
      </div>
    </div>
  </div>

  <div class="wrap">
    <table>
      <thead>
        <tr>
          <th style="width:100px">Severity</th>
          <th style="width:120px">Tool</th>
          <th>Title / Rule</th>
          <th style="width:360px">Location</th>
          <th style="width:120px">CWE</th>
        </tr>
      </thead>
      <tbody id="tb"></tbody>
    </table>
  </div>

<script>
(async function(){
  const tb = document.getElementById('tb');
  const q = document.getElementById('q');
  const sev = document.getElementById('sev');
  const tool = document.getElementById('tool');
  const meta = document.getElementById('meta');

  function esc(s){ return (s??'').toString().replace(/[&<>"']/g, c=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }

  const res = await fetch('/api/vsp/findings?limit=5000');
  const data = await res.json();
  const items = (data.items||[]);

  // fill filters
  const sevs = Array.from(new Set(items.map(x=>x.severity).filter(Boolean))).sort();
  const tools = Array.from(new Set(items.map(x=>x.tool).filter(Boolean))).sort();
  for(const s of sevs){ const o=document.createElement('option'); o.value=s; o.textContent=s; sev.appendChild(o); }
  for(const t of tools){ const o=document.createElement('option'); o.value=t; o.textContent=t; tool.appendChild(o); }

  function norm(s){ return (s??'').toString().toLowerCase(); }

  function render(){
    const qs = norm(q.value);
    const fs = sev.value;
    const ft = tool.value;
    let out = [];
    for(const x of items){
      if(fs && x.severity!==fs) continue;
      if(ft && x.tool!==ft) continue;
      if(qs){
        const hay = norm([x.title,x.rule_id,x.path,x.cwe,x.tool,x.message].join(' '));
        if(!hay.includes(qs)) continue;
      }
      out.push(x);
    }
    meta.textContent = `items: ${out.length} / ${items.length}`;
    tb.innerHTML = out.slice(0,2000).map(x=>`
      <tr>
        <td class="sev ${esc(x.severity||'')}">${esc(x.severity||'')}</td>
        <td class="mono">${esc(x.tool||'')}</td>
        <td>
          <div style="font-weight:700">${esc(x.title||'(no title)')}</div>
          <div class="small muted mono">${esc(x.rule_id||'')}</div>
          <div class="small muted">${esc(x.message||'')}</div>
        </td>
        <td class="mono small">
          <div>${esc(x.path||'')}</div>
          <div class="muted">${esc(x.location||'')}</div>
        </td>
        <td class="mono small">${esc(x.cwe||'')}</td>
      </tr>
    `).join('');
  }

  q.addEventListener('input', ()=>render());
  sev.addEventListener('change', ()=>render());
  tool.addEventListener('change', ()=>render());
  render();
})();
</script>
</body>
</html>
HTML

# 2) patch app routes
python3 - <<'PY'
from pathlib import Path
import re, json
MARK="VSP_DATA_SOURCE_P0_V1"
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

# ensure flask imports
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", s, flags=re.M)
need = ["render_template","jsonify","request"]
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

inject = f"""
# === {MARK} ===
def _vsp_findings_src_default():
    # P0: use the same source as selfcheck currently reports
    from pathlib import Path
    ui_root = Path(__file__).resolve().parent
    cands = [
        ui_root / "findings_unified.json",
        ui_root / "out_ci" / "reports" / "findings_unified.json",
        ui_root / "out_ci" / "findings_unified.json",
    ]
    for fp in cands:
        if fp.exists():
            return fp
    return cands[0]

def _vsp_load_findings_items():
    import json
    fp = _vsp_findings_src_default()
    try:
        j = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return fp, []
    items = j.get("items") or j.get("findings") or []
    out=[]
    for it in items:
        tool = it.get("tool") or it.get("scanner") or it.get("source")
        sev = it.get("severity") or it.get("sev")
        title = it.get("title") or it.get("name") or it.get("check_id") or it.get("rule") or ""
        rule = it.get("rule_id") or it.get("check_id") or it.get("id") or ""
        cwe = it.get("cwe") or it.get("cwe_id") or ""
        path = it.get("path") or it.get("file") or it.get("location") or ""
        loc = it.get("location") or ""
        msg = it.get("message") or it.get("desc") or it.get("description") or ""
        out.append({{
            "tool": tool, "severity": sev, "title": title, "rule_id": rule,
            "cwe": cwe, "path": path, "location": loc, "message": msg
        }})
    return fp, out

@app.get("/data")
def vsp_data_source():
    return render_template("vsp_data_source_v1.html")

@app.get("/api/vsp/findings")
def vsp_api_findings():
    from flask import request
    fp, items = _vsp_load_findings_items()
    try:
        limit = int(request.args.get("limit","2000"))
    except Exception:
        limit = 2000
    return jsonify({{
        "ok": True,
        "who": "{MARK}",
        "src": str(fp),
        "items_len": len(items),
        "items": items[:max(1, min(limit, 20000))]
    }})
# === /{MARK} ===
""".strip()

s = s + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected /data + /api/vsp/findings")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 then verify:"
echo "  curl -sS http://127.0.0.1:8910/api/vsp/findings | jq .ok,.items_len,.src -C"
echo "  xdg-open http://127.0.0.1:8910/data  (or open in browser)"
