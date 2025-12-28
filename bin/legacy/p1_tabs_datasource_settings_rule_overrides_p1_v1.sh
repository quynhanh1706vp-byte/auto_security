#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need awk

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

JS1="static/js/vsp_bundle_commercial_v2.js"
JS2="static/js/vsp_bundle_commercial_v1.js"
mkdir -p static/js templates

# backup
cp -f "$W" "${W}.bak_tabs3_${TS}"
[ -f "$JS1" ] && cp -f "$JS1" "${JS1}.bak_tabs3_${TS}" || true
[ -f "$JS2" ] && cp -f "$JS2" "${JS2}.bak_tabs3_${TS}" || true

python3 - <<'PY'
from pathlib import Path
import json, re, time

ROOT = Path(".").resolve()

# --------------------------
# 1) Create backend blueprint module
# --------------------------
bp = ROOT / "vsp_tabs_extras_bp_v1.py"
if not bp.exists():
    bp.write_text(r'''# -*- coding: utf-8 -*-
"""
VSP Tabs Extras BP v1
- Data Source: /api/vsp/findings_v1
- Settings   : /api/vsp/settings_v1   (GET/POST)
- Overrides  : /api/vsp/rule_overrides_v1 (GET/POST)
Storage:
- Settings:  ui/out_ci/vsp_settings_v1/settings.json
- Overrides: ui/out_ci/rule_overrides_v1/rules.json
"""
from __future__ import annotations
from flask import Blueprint, jsonify, request
from pathlib import Path
import os, json, time

vsp_tabs_extras_bp = Blueprint("vsp_tabs_extras_bp_v1", __name__)

def _now():
    return int(time.time())

def _ui_root() -> Path:
    # current working dir is /home/test/Data/SECURITY_BUNDLE/ui in your layout
    return Path(os.environ.get("VSP_UI_ROOT", str(Path.cwd()))).resolve()

def _out_root_candidates():
    # prefer explicit env, else common defaults
    env = os.environ.get("SECURITY_BUNDLE_OUT") or os.environ.get("VSP_OUT_DIR")
    if env:
        return [Path(env)]
    # common in your project
    return [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]

def _find_latest_run_dir() -> Path | None:
    # latest dir by mtime that contains findings_unified.json (in common places)
    cand_roots = [p for p in _out_root_candidates() if p.exists()]
    run_dirs = []
    for r in cand_roots:
        # direct runs
        for d in r.glob("RUN_*"):
            if d.is_dir():
                run_dirs.append(d)
        # CI style: out_ci/RUN_*/...
        for d in r.glob("**/RUN_*"):
            if d.is_dir():
                run_dirs.append(d)

    # if none found, fallback to newest directory under roots
    if not run_dirs:
        for r in cand_roots:
            for d in r.iterdir():
                if d.is_dir():
                    run_dirs.append(d)

    def score(d: Path):
        try:
            return d.stat().st_mtime
        except Exception:
            return 0

    run_dirs = sorted(set(run_dirs), key=score, reverse=True)

    # pick first that has findings_unified.json in typical locations
    rels = [
        Path("reports/findings_unified.json"),
        Path("findings_unified.json"),
        Path("findings/findings_unified.json"),
        Path("reports/findings_unified.sarif"),
    ]
    for d in run_dirs[:250]:
        for rel in rels:
            if (d / rel).exists():
                return d
    return run_dirs[0] if run_dirs else None

def _load_findings_unified(run_dir: Path) -> list[dict]:
    # try multiple locations
    rels = [
        Path("reports/findings_unified.json"),
        Path("findings_unified.json"),
        Path("findings/findings_unified.json"),
    ]
    p = None
    for rel in rels:
        pp = run_dir / rel
        if pp.exists():
            p = pp; break
    if not p:
        return []
    try:
        data = json.loads(p.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return []

    # support multiple shapes
    if isinstance(data, list):
        return [x for x in data if isinstance(x, dict)]
    if isinstance(data, dict):
        for k in ("items","findings","results","rows"):
            v = data.get(k)
            if isinstance(v, list):
                return [x for x in v if isinstance(x, dict)]
        # single finding?
        return [data]
    return []

def _norm_sev(x: str) -> str:
    if not x: return "INFO"
    x = str(x).strip().upper()
    # normalize to your 6 levels
    if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"):
        return x
    # common mappings
    m = {
        "ERROR":"HIGH",
        "WARN":"MEDIUM",
        "WARNING":"MEDIUM",
        "INFORMATIONAL":"INFO",
        "UNKNOWN":"INFO",
        "NONE":"INFO",
    }
    return m.get(x, "INFO")

def _row_from_any(d: dict) -> dict:
    # tolerant extraction
    sev = _norm_sev(d.get("severity") or d.get("sev") or d.get("level"))
    tool = d.get("tool") or d.get("scanner") or d.get("engine") or "unknown"
    rule = d.get("rule_id") or d.get("rule") or d.get("check_id") or d.get("id") or ""
    msg  = d.get("message") or d.get("msg") or d.get("title") or d.get("description") or ""
    file = d.get("file") or d.get("path") or d.get("filename") or ""
    line = d.get("line") or d.get("start_line") or d.get("line_number") or ""
    cwe  = d.get("cwe") or d.get("cwe_id") or d.get("cweId") or ""
    conf = d.get("confidence") or d.get("precision") or ""
    rid  = d.get("run_id") or d.get("rid") or ""
    return {
        "severity": sev,
        "tool": str(tool),
        "rule_id": str(rule),
        "message": str(msg)[:2000],
        "file": str(file),
        "line": line,
        "cwe": cwe,
        "confidence": conf,
        "run_id": str(rid),
    }

def _counts(items: list[dict]) -> dict:
    c = {k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}
    for it in items:
        c[_norm_sev(it.get("severity"))] += 1
    c["TOTAL"] = sum(c.values())
    return c

@vsp_tabs_extras_bp.get("/api/vsp/findings_v1")
def api_findings_v1():
    limit = int(request.args.get("limit", "20") or 20)
    offset = int(request.args.get("offset", "0") or 0)
    q = (request.args.get("q") or "").strip().lower()
    sev = (request.args.get("severity") or "").strip().upper()
    tool = (request.args.get("tool") or "").strip().lower()

    run_dir = _find_latest_run_dir()
    if not run_dir:
        return jsonify({"ok": True, "items": [], "total": 0, "counts": _counts([]), "run_dir": None})

    raw = _load_findings_unified(run_dir)
    rows = [_row_from_any(x) for x in raw]

    # filter
    def ok(it: dict) -> bool:
        if sev and _norm_sev(it.get("severity")) != sev:
            return False
        if tool and (it.get("tool","").lower() != tool):
            return False
        if q:
            hay = " ".join([str(it.get(k,"")) for k in ("tool","rule_id","message","file","cwe")]).lower()
            if q not in hay:
                return False
        return True

    rows_f = [r for r in rows if ok(r)]
    total = len(rows_f)
    counts = _counts(rows_f)

    # stable sort: severity desc then tool then rule_id
    sev_rank = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3,"INFO":4,"TRACE":5}
    rows_f.sort(key=lambda r: (sev_rank.get(_norm_sev(r.get("severity")), 9), r.get("tool",""), r.get("rule_id","")))

    items = rows_f[offset: offset+limit]
    return jsonify({
        "ok": True,
        "items": items,
        "total": total,
        "counts": counts,
        "run_dir": str(run_dir),
        "ts": _now(),
        "limit": limit,
        "offset": offset,
        "q": q,
        "severity": sev,
        "tool": tool,
    })

def _state_dir(name: str) -> Path:
    d = _ui_root() / "out_ci" / name
    d.mkdir(parents=True, exist_ok=True)
    return d

@vsp_tabs_extras_bp.get("/api/vsp/settings_v1")
def api_settings_get_v1():
    p = _state_dir("vsp_settings_v1") / "settings.json"
    if p.exists():
        try:
            data = json.loads(p.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            data = {}
    else:
        data = {}
    env = {
        "VSP_UI_ROOT": str(_ui_root()),
        "SECURITY_BUNDLE_OUT": os.environ.get("SECURITY_BUNDLE_OUT",""),
        "VSP_OUT_DIR": os.environ.get("VSP_OUT_DIR",""),
    }
    return jsonify({"ok": True, "settings": data, "env": env, "path": str(p), "ts": _now()})

@vsp_tabs_extras_bp.post("/api/vsp/settings_v1")
def api_settings_set_v1():
    p = _state_dir("vsp_settings_v1") / "settings.json"
    body = request.get_json(silent=True) or {}
    settings = body.get("settings", body)
    if not isinstance(settings, dict):
        return jsonify({"ok": False, "err": "settings must be object"}), 400
    p.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "ts": _now()})

@vsp_tabs_extras_bp.get("/api/vsp/rule_overrides_v1")
def api_overrides_get_v1():
    p = _state_dir("rule_overrides_v1") / "rules.json"
    if p.exists():
        try:
            data = json.loads(p.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            data = {"rules":[]}
    else:
        data = {"rules":[]}
    if isinstance(data, list):
        data = {"rules": data}
    if not isinstance(data, dict):
        data = {"rules":[]}
    if not isinstance(data.get("rules"), list):
        data["rules"] = []
    return jsonify({"ok": True, "data": data, "path": str(p), "ts": _now()})

@vsp_tabs_extras_bp.post("/api/vsp/rule_overrides_v1")
def api_overrides_set_v1():
    p = _state_dir("rule_overrides_v1") / "rules.json"
    body = request.get_json(silent=True) or {}
    data = body.get("data", body)
    # accept list or dict
    if isinstance(data, list):
        data = {"rules": data}
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        return jsonify({"ok": False, "err": "expect {data:{rules:[...]}} or {rules:[...]} or [...]"}), 400
    # light validation + normalize
    norm = []
    for r in data["rules"]:
        if not isinstance(r, dict): 
            continue
        norm.append({
            "id": r.get("id",""),
            "tool": r.get("tool",""),
            "rule_id": r.get("rule_id",""),
            "action": r.get("action",""),  # e.g. "ignore" / "downgrade" / "upgrade"
            "severity": r.get("severity",""),  # override severity (CRITICAL..TRACE)
            "reason": r.get("reason",""),
            "expires": r.get("expires",""),
        })
    out = {"rules": norm, "updated_ts": _now()}
    p.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    # optional "apply" flag for other pipeline components to watch
    (_state_dir("rule_overrides_v1") / "APPLY.flag").write_text(str(_now()), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "rules_n": len(norm), "ts": _now()})
''', encoding="utf-8")
    print("[OK] created", bp)
else:
    print("[OK] exists", bp)

# --------------------------
# 2) Patch gateway to register blueprint (safe)
# --------------------------
w = ROOT / "wsgi_vsp_ui_gateway.py"
s = w.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_TABS3_BP_REGISTER_V1"
if marker not in s:
    inject = r'''
# --- VSP_P1_TABS3_BP_REGISTER_V1 ---
try:
    from vsp_tabs_extras_bp_v1 import vsp_tabs_extras_bp as _vsp_tabs_extras_bp_v1
    # register only if Flask app is available
    if "app" in globals() and hasattr(globals()["app"], "register_blueprint"):
        globals()["app"].register_blueprint(_vsp_tabs_extras_bp_v1)
        print("[VSP_TABS3] registered blueprint: vsp_tabs_extras_bp_v1")
    else:
        print("[VSP_TABS3] skip register (no app in globals)")
except Exception as _e:
    print("[VSP_TABS3] blueprint disabled:", _e)
# --- /VSP_P1_TABS3_BP_REGISTER_V1 ---
'''
    # try to place near the end, after app creation if possible
    # If we find "app =" assign, insert after first occurrence block-ish
    m = re.search(r'(^\s*app\s*=\s*Flask\([^\n]*\)\s*$)', s, flags=re.M)
    if m:
        pos = m.end()
        s = s[:pos] + "\n" + inject + s[pos:]
        print("[OK] injected blueprint register after app=Flask(...)")
    else:
        s = s + "\n" + inject
        print("[WARN] app=Flask not found; appended blueprint register at EOF")
    w.write_text(s, encoding="utf-8")
else:
    print("[OK] marker already in", w)

# --------------------------
# 3) Ensure minimal templates exist + add tab root mount
# --------------------------
tpls = {
    "templates/vsp_data_source_2025.html": "data_source",
    "templates/vsp_settings_2025.html": "settings",
    "templates/vsp_rule_overrides_2025.html": "rule_overrides",
}
for p_str, tab in tpls.items():
    p = ROOT / p_str
    if not p.exists():
        p.write_text(f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>VSP 2025 - {tab}</title>
  <link rel="icon" href="/static/favicon.ico"/>
  <style>
    body{{margin:0;background:#0b1220;color:#e5e7eb;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto;}}
    a{{color:#93c5fd;text-decoration:none}}
  </style>
</head>
<body>
  <!-- Minimal page: your global 5-tabs shell can wrap this; JS will render content -->
  <div id="vsp_tab_root" data-vsp-tab="{tab}" style="padding:16px"></div>
  <script>window.__vsp_tab="{tab}";</script>
  <script src="/static/js/vsp_bundle_commercial_v2.js?v={{'{{'}}asset_v{{'}}'}}"></script>
</body>
</html>
""", encoding="utf-8")
        print("[OK] created template", p)
    else:
        ss = p.read_text(encoding="utf-8", errors="replace")
        if 'id="vsp_tab_root"' not in ss:
            ss = ss.replace("</body>", f'\n<div id="vsp_tab_root" data-vsp-tab="{tab}" style="padding:16px"></div>\n<script>window.__vsp_tab="{tab}";</script>\n</body>')
            p.write_text(ss, encoding="utf-8")
            print("[OK] patched mount root in", p)
        else:
            print("[OK] template already has vsp_tab_root:", p)

# --------------------------
# 4) Patch JS bundle to render 3 tabs (append safely)
# --------------------------
bundles = []
for js in [ROOT/"static/js/vsp_bundle_commercial_v2.js", ROOT/"static/js/vsp_bundle_commercial_v1.js"]:
    if js.exists():
        bundles.append(js)

js_marker = "VSP_P1_TABS3_UI_V1"
ui_code = r'''
/* =======================
   VSP_P1_TABS3_UI_V1
   Data Source + Settings + Rule Overrides
   ======================= */
(() => {
  if (window.__vsp_p1_tabs3_ui_v1) return;
  window.__vsp_p1_tabs3_ui_v1 = true;

  const $ = (sel, root=document) => root.querySelector(sel);
  const esc = (s) => (s==null?'':String(s)).replace(/[&<>"']/g, (c)=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  const sleep = (ms)=>new Promise(r=>setTimeout(r,ms));

  function ensureStyle(){
    if (document.getElementById("vsp_tabs3_style_v1")) return;
    const st = document.createElement("style");
    st.id = "vsp_tabs3_style_v1";
    st.textContent = `
      .vsp-card{background:#0f1b2d;border:1px solid rgba(148,163,184,.18);border-radius:14px;padding:14px}
      .vsp-row{display:flex;gap:12px;flex-wrap:wrap}
      .vsp-kpi{min-width:180px}
      .vsp-muted{color:#94a3b8}
      .vsp-btn{background:#111c30;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:8px 10px;cursor:pointer}
      .vsp-btn:hover{border-color:rgba(148,163,184,.45)}
      .vsp-in{background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:8px 10px;outline:none}
      .vsp-in:focus{border-color:rgba(59,130,246,.55)}
      table.vsp-t{width:100%;border-collapse:separate;border-spacing:0 8px}
      table.vsp-t th{font-weight:600;text-align:left;color:#cbd5e1;font-size:12px;padding:0 10px}
      table.vsp-t td{background:#0b1324;border-top:1px solid rgba(148,163,184,.18);border-bottom:1px solid rgba(148,163,184,.18);padding:10px;font-size:13px;vertical-align:top}
      table.vsp-t tr td:first-child{border-left:1px solid rgba(148,163,184,.18);border-top-left-radius:12px;border-bottom-left-radius:12px}
      table.vsp-t tr td:last-child{border-right:1px solid rgba(148,163,184,.18);border-top-right-radius:12px;border-bottom-right-radius:12px}
      .vsp-badge{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(148,163,184,.22);font-size:12px}
      .vsp-pager{display:flex;gap:10px;align-items:center;justify-content:flex-end;margin-top:10px}
      .vsp-code{width:100%;min-height:280px;resize:vertical;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:12px;padding:12px}
      .vsp-ok{color:#86efac}
      .vsp-err{color:#fca5a5}
    `;
    document.head.appendChild(st);
  }

  async function apiJson(url, opt){
    const r = await fetch(url, opt);
    const t = await r.text();
    let j = null;
    try{ j = JSON.parse(t); }catch(_e){ j = { ok:false, err:"non-json", raw:t.slice(0,800) }; }
    if (!r.ok) throw Object.assign(new Error("HTTP "+r.status), {status:r.status, body:j});
    return j;
  }

  function mount(){
    return $("#vsp_tab_root") || document.body;
  }
  function tabName(){
    return (window.__vsp_tab || ($("#vsp_tab_root")?.getAttribute("data-vsp-tab")) || "").trim();
  }

  // ---------------- Data Source ----------------
  function renderCounts(counts){
    const keys = ["TOTAL","CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    return keys.map(k=>{
      const v = counts?.[k] ?? 0;
      return `<div class="vsp-card vsp-kpi"><div class="vsp-muted" style="font-size:12px">${k}</div><div style="font-size:22px;font-weight:700;margin-top:6px">${v}</div></div>`;
    }).join("");
  }

  async function renderDataSource(){
    ensureStyle();
    const root = mount();
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;align-items:center;margin-bottom:12px">
        <div>
          <div style="font-size:18px;font-weight:800">Data Source</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Table view of findings_unified.json (latest run) with filters & paging</div>
        </div>
        <div class="vsp-row" style="gap:8px">
          <button class="vsp-btn" id="ds_refresh">Refresh</button>
          <button class="vsp-btn" id="ds_dl_json">Download JSON</button>
        </div>
      </div>

      <div class="vsp-row" id="ds_kpis" style="margin-bottom:12px"></div>

      <div class="vsp-card" style="margin-bottom:12px">
        <div class="vsp-row" style="align-items:center">
          <input class="vsp-in" id="ds_q" placeholder="search (tool, rule_id, message, file, cwe)..." style="min-width:260px;flex:1"/>
          <select class="vsp-in" id="ds_sev">
            <option value="">All severities</option>
            <option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option><option>INFO</option><option>TRACE</option>
          </select>
          <input class="vsp-in" id="ds_tool" placeholder="tool (exact, e.g. semgrep)" style="min-width:200px"/>
          <select class="vsp-in" id="ds_limit">
            <option value="10">10 / page</option>
            <option value="20" selected>20 / page</option>
            <option value="50">50 / page</option>
          </select>
        </div>
        <div class="vsp-muted" id="ds_meta" style="margin-top:10px;font-size:12px"></div>
      </div>

      <div class="vsp-card">
        <table class="vsp-t">
          <thead>
            <tr>
              <th>Severity</th><th>Tool</th><th>Rule</th><th>File</th><th>Line</th><th>Message</th>
            </tr>
          </thead>
          <tbody id="ds_tbody"></tbody>
        </table>
        <div class="vsp-pager">
          <button class="vsp-btn" id="ds_prev">Prev</button>
          <div class="vsp-muted" id="ds_page">Page 1/1</div>
          <button class="vsp-btn" id="ds_next">Next</button>
        </div>
      </div>
    `;

    let state = { offset:0, limit:20, total:0, last:null };

    const qEl = $("#ds_q"), sevEl=$("#ds_sev"), toolEl=$("#ds_tool"), limEl=$("#ds_limit");
    const kpis = $("#ds_kpis"), tbody=$("#ds_tbody"), meta=$("#ds_meta"), page=$("#ds_page");

    async function load(){
      const q = (qEl.value||"").trim();
      const severity = (sevEl.value||"").trim();
      const tool = (toolEl.value||"").trim();
      const limit = parseInt(limEl.value||"20",10) || 20;
      state.limit = limit;

      const url = `/api/vsp/findings_v1?limit=${encodeURIComponent(limit)}&offset=${encodeURIComponent(state.offset)}&q=${encodeURIComponent(q)}&severity=${encodeURIComponent(severity)}&tool=${encodeURIComponent(tool.toLowerCase())}`;
      const j = await apiJson(url);
      state.total = j.total||0;
      state.last = j;
      kpis.innerHTML = renderCounts(j.counts||{});
      meta.innerHTML = `run_dir: <span class="vsp-muted">${esc(j.run_dir||"")}</span> · total_filtered: <b>${esc(j.total||0)}</b> · limit=${esc(j.limit)} offset=${esc(j.offset)}`;

      const items = j.items||[];
      tbody.innerHTML = items.map(it=>{
        const sev = esc(it.severity||"");
        const tool = esc(it.tool||"");
        const rule = esc(it.rule_id||"");
        const file = esc(it.file||"");
        const line = esc(it.line||"");
        const msg  = esc(it.message||"");
        return `<tr>
          <td><span class="vsp-badge">${sev}</span></td>
          <td>${tool}</td>
          <td>${rule}</td>
          <td style="max-width:360px;word-break:break-word">${file}</td>
          <td>${line}</td>
          <td style="max-width:520px;word-break:break-word">${msg}</td>
        </tr>`;
      }).join("");

      const pages = Math.max(1, Math.ceil((state.total||0)/state.limit));
      const cur = Math.min(pages, Math.floor((state.offset||0)/state.limit)+1);
      page.textContent = `Page ${cur}/${pages}`;
      $("#ds_prev").disabled = (state.offset<=0);
      $("#ds_next").disabled = (state.offset + state.limit >= state.total);
    }

    function debounce(fn, ms=250){
      let t=null;
      return ()=>{ clearTimeout(t); t=setTimeout(fn, ms); };
    }
    const reloadDebounced = debounce(()=>{ state.offset=0; load().catch(e=>console.error(e)); }, 250);

    qEl.addEventListener("input", reloadDebounced);
    sevEl.addEventListener("change", ()=>{ state.offset=0; load().catch(console.error); });
    toolEl.addEventListener("input", reloadDebounced);
    limEl.addEventListener("change", ()=>{ state.offset=0; load().catch(console.error); });

    $("#ds_refresh").onclick = ()=>{ load().catch(console.error); };
    $("#ds_prev").onclick = ()=>{ state.offset = Math.max(0, state.offset - state.limit); load().catch(console.error); };
    $("#ds_next").onclick = ()=>{ state.offset = state.offset + state.limit; load().catch(console.error); };

    $("#ds_dl_json").onclick = ()=>{
      const data = state.last || {};
      const blob = new Blob([JSON.stringify(data, null, 2)], {type:"application/json"});
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "vsp_findings_v1.json";
      a.click();
      setTimeout(()=>URL.revokeObjectURL(a.href), 1200);
    };

    await load();
  }

  // ---------------- Settings ----------------
  async function renderSettings(){
    ensureStyle();
    const root = mount();
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;align-items:center;margin-bottom:12px">
        <div>
          <div style="font-size:18px;font-weight:800">Settings</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Commercial-friendly config JSON (GET/POST)</div>
        </div>
        <div class="vsp-row" style="gap:8px">
          <button class="vsp-btn" id="st_reload">Reload</button>
          <button class="vsp-btn" id="st_save">Save</button>
          <button class="vsp-btn" id="st_dl">Download</button>
        </div>
      </div>

      <div class="vsp-row" style="margin-bottom:12px">
        <div class="vsp-card" style="flex:1;min-width:320px">
          <div class="vsp-muted" style="font-size:12px">Environment</div>
          <pre id="st_env" style="white-space:pre-wrap;margin:10px 0 0 0;font-size:12px;color:#cbd5e1"></pre>
        </div>
        <div class="vsp-card" style="flex:1;min-width:320px">
          <div class="vsp-muted" style="font-size:12px">Storage</div>
          <div id="st_path" class="vsp-muted" style="margin-top:10px;font-size:12px"></div>
          <div id="st_msg" style="margin-top:10px;font-size:12px"></div>
        </div>
      </div>

      <div class="vsp-card">
        <div class="vsp-muted" style="font-size:12px;margin-bottom:8px">settings.json</div>
        <textarea id="st_text" class="vsp-code" spellcheck="false"></textarea>
      </div>
    `;

    const envEl = $("#st_env"), pathEl=$("#st_path"), msgEl=$("#st_msg"), txt=$("#st_text");

    async function load(){
      msgEl.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await apiJson("/api/vsp/settings_v1");
      envEl.textContent = JSON.stringify(j.env||{}, null, 2);
      pathEl.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.settings||{}, null, 2);
      msgEl.innerHTML = `<span class="vsp-ok">OK</span> · ts=${esc(j.ts||"")}`;
      return j;
    }

    async function save(){
      let obj = {};
      try { obj = JSON.parse(txt.value||"{}"); }
      catch(e){ msgEl.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return; }
      msgEl.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await apiJson("/api/vsp/settings_v1", {
        method:"POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify({settings: obj})
      });
      msgEl.innerHTML = `<span class="vsp-ok">Saved</span> · ${esc(j.path||"")}`;
      return j;
    }

    $("#st_reload").onclick = ()=>load().catch(e=>{ msgEl.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`; });
    $("#st_save").onclick = ()=>save().catch(e=>{ msgEl.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`; });
    $("#st_dl").onclick = ()=>{
      const blob = new Blob([txt.value||"{}"], {type:"application/json"});
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "vsp_settings.json";
      a.click();
      setTimeout(()=>URL.revokeObjectURL(a.href), 1200);
    };

    await load();
  }

  // ---------------- Rule Overrides ----------------
  async function renderRuleOverrides(){
    ensureStyle();
    const root = mount();
    root.innerHTML = `
      <div class="vsp-row" style="justify-content:space-between;align-items:center;margin-bottom:12px">
        <div>
          <div style="font-size:18px;font-weight:800">Rule Overrides</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Manage custom overrides (GET/POST) · stored under ui/out_ci/rule_overrides_v1/rules.json</div>
        </div>
        <div class="vsp-row" style="gap:8px">
          <button class="vsp-btn" id="ro_reload">Reload</button>
          <button class="vsp-btn" id="ro_validate">Validate</button>
          <button class="vsp-btn" id="ro_save">Save</button>
          <button class="vsp-btn" id="ro_dl">Download</button>
        </div>
      </div>

      <div class="vsp-row" style="margin-bottom:12px">
        <div class="vsp-card" style="flex:1;min-width:320px">
          <div class="vsp-muted" style="font-size:12px">Quick Schema</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:8px;line-height:1.5">
            Each rule: {"id","tool","rule_id","action","severity","reason","expires"}<br/>
            action examples: "ignore" | "downgrade" | "upgrade"<br/>
            severity override: CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE
          </div>
        </div>
        <div class="vsp-card" style="flex:1;min-width:320px">
          <div class="vsp-muted" style="font-size:12px">Status</div>
          <div id="ro_path" class="vsp-muted" style="margin-top:10px;font-size:12px"></div>
          <div id="ro_msg" style="margin-top:10px;font-size:12px"></div>
        </div>
      </div>

      <div class="vsp-card">
        <div class="vsp-muted" style="font-size:12px;margin-bottom:8px">rules.json</div>
        <textarea id="ro_text" class="vsp-code" spellcheck="false"></textarea>
      </div>
    `;

    const pathEl=$("#ro_path"), msgEl=$("#ro_msg"), txt=$("#ro_text");

    function normalize(obj){
      // accept list or {rules:[...]}
      if (Array.isArray(obj)) obj = {rules: obj};
      if (!obj || typeof obj !== "object") throw new Error("Root must be object or array");
      if (!Array.isArray(obj.rules)) obj.rules = [];
      // ensure objects
      obj.rules = obj.rules.filter(x=>x && typeof x==="object" && !Array.isArray(x));
      return obj;
    }

    async function load(){
      msgEl.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await apiJson("/api/vsp/rule_overrides_v1");
      pathEl.textContent = `path: ${j.path||""}`;
      const data = j.data || {rules:[]};
      txt.value = JSON.stringify(data, null, 2);
      msgEl.innerHTML = `<span class="vsp-ok">OK</span> · rules=${esc((data.rules||[]).length)} · ts=${esc(j.ts||"")}`;
    }

    function validate(){
      let obj;
      try { obj = JSON.parse(txt.value||"{}"); obj = normalize(obj); }
      catch(e){ msgEl.innerHTML = `<span class="vsp-err">Invalid:</span> ${esc(e.message||String(e))}`; return null; }
      // light validation
      for (const r of obj.rules){
        if (!("tool" in r) || !("rule_id" in r)){
          msgEl.innerHTML = `<span class="vsp-err">Invalid rule:</span> each rule needs tool + rule_id`; return null;
        }
      }
      msgEl.innerHTML = `<span class="vsp-ok">Valid</span> · rules=${esc(obj.rules.length)}`;
      return obj;
    }

    async function save(){
      const obj = validate();
      if (!obj) return;
      msgEl.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await apiJson("/api/vsp/rule_overrides_v1", {
        method:"POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify({data: obj})
      });
      msgEl.innerHTML = `<span class="vsp-ok">Saved</span> · rules_n=${esc(j.rules_n||"")} · ts=${esc(j.ts||"")}`;
      await sleep(150);
      await load();
    }

    $("#ro_reload").onclick = ()=>load().catch(e=>{ msgEl.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`; });
    $("#ro_validate").onclick = ()=>validate();
    $("#ro_save").onclick = ()=>save().catch(e=>{ msgEl.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`; });
    $("#ro_dl").onclick = ()=>{
      const blob = new Blob([txt.value||"{}"], {type:"application/json"});
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "vsp_rule_overrides.json";
      a.click();
      setTimeout(()=>URL.revokeObjectURL(a.href), 1200);
    };

    await load();
  }

  // --------------- Router ---------------
  async function boot(){
    const t = tabName() || location.pathname.replace(/^\//,'');
    try{
      if (t.includes("data_source")) return await renderDataSource();
      if (t.includes("settings")) return await renderSettings();
      if (t.includes("rule_overrides")) return await renderRuleOverrides();
    }catch(e){
      console.error(e);
      const root = mount();
      root.innerHTML = `<div class="vsp-card"><div style="font-weight:800">Tab render failed</div><pre style="white-space:pre-wrap;margin-top:10px" class="vsp-muted">${esc(e.message||String(e))}</pre></div>`;
    }
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
'''
for js in bundles:
    ss = js.read_text(encoding="utf-8", errors="replace")
    if js_marker not in ss:
        ss2 = ss + "\n\n" + ui_code + "\n"
        js.write_text(ss2, encoding="utf-8")
        print("[OK] appended tabs UI to", js)
    else:
        print("[OK] JS marker already in", js)

PY

echo "== py_compile =="
python3 -m py_compile vsp_tabs_extras_bp_v1.py wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

if command -v node >/dev/null 2>&1; then
  [ -f "$JS1" ] && node --check "$JS1" && echo "[OK] node --check $JS1" || true
  [ -f "$JS2" ] && node --check "$JS2" && echo "[OK] node --check $JS2" || true
fi

echo "== quick grep markers =="
grep -RIn --exclude='*.bak_*' "VSP_P1_TABS3_UI_V1" static/js 2>/dev/null | head -n 5 || true
grep -RIn --exclude='*.bak_*' "VSP_P1_TABS3_BP_REGISTER_V1" "$W" 2>/dev/null | head -n 5 || true

echo "== done =="
echo "[NEXT] restart UI service then verify:"
echo "  sudo systemctl restart vsp-ui-8910.service || true"
echo "  curl -fsS http://127.0.0.1:8910/data_source | head"
echo "  curl -fsS http://127.0.0.1:8910/settings | head"
echo "  curl -fsS http://127.0.0.1:8910/rule_overrides | head"
echo "  curl -fsS 'http://127.0.0.1:8910/api/vsp/findings_v1?limit=10&offset=0' | head -c 200; echo"
