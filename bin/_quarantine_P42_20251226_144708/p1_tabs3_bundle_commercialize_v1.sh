#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep; need wc

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_tabs3_bundle_${TS}"
echo "[BACKUP] ${W}.bak_tabs3_bundle_${TS}"

mkdir -p static/js templates tools bin out_ci

python3 - <<'PY'
from pathlib import Path
import re, json, time, os

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
W = ROOT/"wsgi_vsp_ui_gateway.py"

# -------------------------
# 1) Write/overwrite Blueprint v4 (runs listing, findings by RID, rule apply, settings effective)
# -------------------------
bp = ROOT/"vsp_tabs3_ui_bp_v4.py"
bp.write_text(r'''# -*- coding: utf-8 -*-
from __future__ import annotations
from flask import Blueprint, jsonify, request
from pathlib import Path
import os, json, time, re, hashlib

vsp_tabs3_ui_bp_v4 = Blueprint("vsp_tabs3_ui_bp_v4", __name__)

def _now(): return int(time.time())

def _ui_root() -> Path:
    return Path(os.environ.get("VSP_UI_ROOT", str(Path.cwd()))).resolve()

def _state_dir(name: str) -> Path:
    d = _ui_root()/"out_ci"/name
    d.mkdir(parents=True, exist_ok=True)
    return d

def _out_roots():
    env = os.environ.get("SECURITY_BUNDLE_OUT") or os.environ.get("VSP_OUT_DIR")
    roots = []
    if env: roots.append(Path(env))
    roots += [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]
    # uniq + exists
    out=[]
    for r in roots:
        if r and r.exists():
            rp = r.resolve()
            if rp not in out: out.append(rp)
    return out

def _scan_run_dirs(limit=600):
    roots = _out_roots()
    run_dirs=[]
    for r in roots:
        # shallow
        for d in r.glob("RUN_*"):
            if d.is_dir(): run_dirs.append(d)
        # deep (some CI nests)
        for d in r.glob("**/RUN_*"):
            if d.is_dir(): run_dirs.append(d)
    # uniq by resolved path
    uniq={}
    for d in run_dirs:
        try:
            uniq[str(d.resolve())]=d.resolve()
        except Exception:
            uniq[str(d)]=d
    run_dirs=list(uniq.values())
    run_dirs.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return run_dirs[:limit]

def _rid_from_dir(d: Path) -> str:
    # rid heuristic: folder name itself
    return d.name

def _find_run_dir_by_rid(rid: str) -> Path|None:
    rid = (rid or "").strip()
    if not rid: return None
    rid_l = rid.lower()
    for d in _scan_run_dirs(limit=1200):
        if rid_l in d.name.lower():
            return d
    return None

def _latest_run_dir() -> Path|None:
    xs = _scan_run_dirs(limit=1)
    return xs[0] if xs else None

def _latest_findings_fp(run_dir: Path) -> Path|None:
    rels = [
        Path("reports/findings_unified.json"),
        Path("findings_unified.json"),
        Path("findings/findings_unified.json"),
    ]
    for rel in rels:
        fp = run_dir/rel
        if fp.exists(): return fp
    return None

def _load_findings(fp: Path):
    try:
        data = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return []
    if isinstance(data, dict):
        for k in ("items","findings","results","rows"):
            if isinstance(data.get(k), list):
                return data[k]
    return data if isinstance(data, list) else []

def _norm_sev(x):
    x = str(x or "").strip().upper()
    if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"): return x
    return {"ERROR":"HIGH","WARN":"MEDIUM","WARNING":"MEDIUM","UNKNOWN":"INFO","NONE":"INFO"}.get(x, "INFO")

def _row(d):
    return {
        "severity": _norm_sev(d.get("severity") or d.get("sev") or d.get("level")),
        "tool": str(d.get("tool") or d.get("scanner") or d.get("engine") or "unknown"),
        "rule_id": str(d.get("rule_id") or d.get("rule") or d.get("check_id") or d.get("id") or ""),
        "message": str(d.get("message") or d.get("msg") or d.get("title") or d.get("description") or "")[:2000],
        "file": str(d.get("file") or d.get("path") or d.get("filename") or ""),
        "line": d.get("line") or d.get("start_line") or d.get("line_number") or "",
        "cwe": d.get("cwe") or d.get("cwe_id") or "",
        "confidence": d.get("confidence") or d.get("precision") or "",
        "_raw": d,
    }

def _counts(items):
    c = {k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}
    for it in items: c[_norm_sev(it.get("severity"))] += 1
    c["TOTAL"] = sum(c.values())
    return c

@vsp_tabs3_ui_bp_v4.get("/api/ui/runs_v1")
def api_ui_runs_v1():
    limit = int(request.args.get("limit","120") or 120)
    items=[]
    for d in _scan_run_dirs(limit=max(60, min(2000, limit))):
        try:
            items.append({
                "rid": _rid_from_dir(d),
                "run_dir": str(d),
                "mtime": int(d.stat().st_mtime),
            })
        except Exception:
            items.append({"rid": _rid_from_dir(d), "run_dir": str(d), "mtime": 0})
    return jsonify({"ok": True, "items": items[:limit], "total": len(items), "ts": _now()})

@vsp_tabs3_ui_bp_v4.get("/api/ui/findings_v2")
def api_ui_findings_v2():
    limit = int(request.args.get("limit","20") or 20)
    offset = int(request.args.get("offset","0") or 0)
    q = (request.args.get("q") or "").strip().lower()
    sev = (request.args.get("severity") or "").strip().upper()
    tool = (request.args.get("tool") or "").strip().lower()
    rid = (request.args.get("rid") or "").strip()

    run_dir = _find_run_dir_by_rid(rid) if rid else _latest_run_dir()
    if not run_dir:
        return jsonify({"ok": True, "items": [], "total": 0, "counts": _counts([]),
                        "rid": rid or None, "run_dir": None, "hint": "no RUN_* directories found", "ts": _now()})

    fp = _latest_findings_fp(run_dir)
    if not fp:
        return jsonify({"ok": True, "items": [], "total": 0, "counts": _counts([]),
                        "rid": rid or run_dir.name, "run_dir": str(run_dir),
                        "hint": "no findings_unified.json found under run_dir; expected reports/findings_unified.json or findings_unified.json",
                        "ts": _now()})

    raw = _load_findings(fp)
    rows = [_row(x) for x in raw if isinstance(x, dict)]

    def ok(it):
        if sev and _norm_sev(it.get("severity")) != sev: return False
        if tool and it.get("tool","").lower() != tool: return False
        if q:
            hay = " ".join([str(it.get(k,"")) for k in ("tool","rule_id","message","file","cwe")]).lower()
            if q not in hay: return False
        return True

    rows = [r for r in rows if ok(r)]
    total = len(rows)
    counts = _counts(rows)
    rank = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3,"INFO":4,"TRACE":5}
    rows.sort(key=lambda r: (rank.get(_norm_sev(r.get("severity")), 9), r.get("tool",""), r.get("rule_id","")))
    items = rows[offset:offset+limit]
    # drop _raw in response (heavy)
    for it in items:
        it.pop("_raw", None)
    return jsonify({"ok": True, "items": items, "total": total, "counts": counts,
                    "rid": rid or run_dir.name, "run_dir": str(run_dir), "fp": str(fp),
                    "limit": limit, "offset": offset, "q": q, "severity": sev, "tool": tool,
                    "ts": _now()})

def _load_rule_overrides():
    p = _state_dir("rule_overrides_v2")/"rules.json"
    try:
        data = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {"rules":[]}
    except Exception:
        data = {"rules":[]}
    if isinstance(data, list): data={"rules": data}
    if not isinstance(data, dict): data={"rules":[]}
    if not isinstance(data.get("rules"), list): data["rules"]=[]
    return p, data

def _rule_key(tool: str, rule_id: str) -> str:
    return (tool.strip().lower() + "::" + rule_id.strip()).strip()

def _apply_overrides(findings: list[dict], rules: list[dict]):
    # rules schema: {tool, rule_id, action: ignore|downgrade|upgrade, severity(optional), reason(optional)}
    m={}
    for r in rules:
        if not isinstance(r, dict): continue
        tool = str(r.get("tool","")).strip()
        rule_id = str(r.get("rule_id","")).strip()
        if not tool or not rule_id: continue
        m[_rule_key(tool, rule_id)] = r

    out=[]
    stats={"ignored":0,"downgraded":0,"upgraded":0,"touched":0}
    for f in findings:
        if not isinstance(f, dict):
            continue
        tool = str(f.get("tool") or f.get("scanner") or f.get("engine") or "unknown")
        rule_id = str(f.get("rule_id") or f.get("rule") or f.get("check_id") or f.get("id") or "")
        k=_rule_key(tool, rule_id)
        r = m.get(k)
        if not r:
            out.append(f); continue

        action = str(r.get("action","")).strip().lower()
        stats["touched"] += 1

        if action == "ignore":
            stats["ignored"] += 1
            continue

        sev_new = r.get("severity")
        if sev_new:
            # map to normalized
            sev_new = _norm_sev(sev_new)
        else:
            sev_new = None

        # mutate a copy
        g = dict(f)
        g["override"] = {
            "action": action,
            "severity": sev_new,
            "reason": str(r.get("reason",""))[:500],
            "ts": _now(),
        }

        if action in ("downgrade","upgrade") and sev_new:
            old = _norm_sev(g.get("severity") or g.get("sev") or g.get("level"))
            g["severity"] = sev_new
            if action == "downgrade":
                stats["downgraded"] += 1
            else:
                stats["upgraded"] += 1
            g["override"]["from"] = old
        out.append(g)
    return out, stats

@vsp_tabs3_ui_bp_v4.get("/api/ui/rule_overrides_apply_v1")
def api_ui_rule_apply_v1():
    rid = (request.args.get("rid") or "").strip()
    run_dir = _find_run_dir_by_rid(rid) if rid else _latest_run_dir()
    if not run_dir:
        return jsonify({"ok": False, "err": "no RUN_* directories found", "rid": rid or None, "ts": _now()}), 404
    fp = _latest_findings_fp(run_dir)
    if not fp:
        return jsonify({"ok": False, "err": "no findings_unified.json found for run_dir", "run_dir": str(run_dir), "rid": rid or run_dir.name, "ts": _now()}), 404

    rules_fp, rules_data = _load_rule_overrides()
    rules = rules_data.get("rules", [])

    findings = _load_findings(fp)
    applied, stats = _apply_overrides(findings, rules)

    out_fp = run_dir/"reports"/"findings_unified_overridden.json"
    out_fp.parent.mkdir(parents=True, exist_ok=True)
    out_fp.write_text(json.dumps({"items": applied, "meta": {"rid": rid or run_dir.name, "run_dir": str(run_dir),
                                                           "source_fp": str(fp), "rules_fp": str(rules_fp),
                                                           "stats": stats, "ts": _now()}},
                                 ensure_ascii=False, indent=2), encoding="utf-8")

    return jsonify({"ok": True, "rid": rid or run_dir.name, "run_dir": str(run_dir),
                    "source_fp": str(fp), "rules_fp": str(rules_fp), "out_fp": str(out_fp),
                    "stats": stats, "rules_n": len(rules), "ts": _now()})

@vsp_tabs3_ui_bp_v4.get("/api/ui/settings_v2")
def api_ui_settings_get_v2():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    try:
        settings = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {}
    except Exception:
        settings = {}
    return jsonify({"ok": True, "settings": settings, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v4.post("/api/ui/settings_v2")
def api_ui_settings_set_v2():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    body = request.get_json(silent=True) or {}
    settings = body.get("settings", body)
    if not isinstance(settings, dict):
        return jsonify({"ok": False, "err": "settings must be object"}), 400
    p.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "ts": _now()})

def _settings_effective(settings: dict):
    # minimal commercial mapping
    timeouts = settings.get("timeouts") if isinstance(settings.get("timeouts"), dict) else {}
    tools_enabled = settings.get("tools_enabled") if isinstance(settings.get("tools_enabled"), dict) else {}
    degrade = settings.get("degrade_graceful", True)

    def geti(k, default):
        v = timeouts.get(k, default)
        try: return int(v)
        except Exception: return default

    eff = {
        "degrade_graceful": bool(degrade),
        "timeouts": {
            "kics_sec": geti("kics_sec", 900),
            "codeql_sec": geti("codeql_sec", 1800),
            "trivy_sec": geti("trivy_sec", 900),
        },
        "tools_enabled": {},
    }
    # default true if not set
    default_tools = ["bandit","semgrep","gitleaks","kics","trivy","syft","grype","codeql"]
    for t in default_tools:
        v = tools_enabled.get(t, True)
        eff["tools_enabled"][t] = bool(v) if isinstance(v, (bool,int)) else (str(v).strip().lower() not in ("0","false","no","off"))
    return eff

@vsp_tabs3_ui_bp_v4.get("/api/ui/settings_effective_v1")
def api_ui_settings_effective_v1():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    try:
        settings = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {}
    except Exception:
        settings = {}
    eff = _settings_effective(settings)
    return jsonify({"ok": True, "effective": eff, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v4.get("/api/ui/rule_overrides_v2")
def api_ui_rules_get_v2():
    p = _state_dir("rule_overrides_v2")/"rules.json"
    try:
        data = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {"rules":[]}
    except Exception:
        data = {"rules":[]}
    if isinstance(data, list): data = {"rules": data}
    if not isinstance(data, dict): data = {"rules":[]}
    if not isinstance(data.get("rules"), list): data["rules"] = []
    return jsonify({"ok": True, "data": data, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v4.post("/api/ui/rule_overrides_v2")
def api_ui_rules_set_v2():
    p = _state_dir("rule_overrides_v2")/"rules.json"
    body = request.get_json(silent=True) or {}
    data = body.get("data", body)
    if isinstance(data, list): data = {"rules": data}
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        return jsonify({"ok": False, "err": "expect {rules:[...]} or {data:{rules:[...]}} or [...]"}), 400
    out = {"rules": [r for r in data["rules"] if isinstance(r, dict)], "updated_ts": _now()}
    p.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "rules_n": len(out["rules"]), "ts": _now()})
''', encoding="utf-8")
print("[OK] wrote", bp)

# -------------------------
# 2) Patch gateway: register bp v4 (keep short-circuit already present)
# -------------------------
s = W.read_text(encoding="utf-8", errors="replace")
reg_marker = "VSP_TABS3_UI_BP_REGISTER_V4"
if reg_marker not in s:
    s += r'''
# --- VSP_TABS3_UI_BP_REGISTER_V4 ---
try:
    from vsp_tabs3_ui_bp_v4 import vsp_tabs3_ui_bp_v4 as _vsp_tabs3_ui_bp_v4
    if "app" in globals() and hasattr(globals()["app"], "register_blueprint"):
        globals()["app"].register_blueprint(_vsp_tabs3_ui_bp_v4)
        print("[VSP_TABS3_V4] registered blueprint: vsp_tabs3_ui_bp_v4")
except Exception as _e:
    print("[VSP_TABS3_V4] blueprint disabled:", _e)
# --- /VSP_TABS3_UI_BP_REGISTER_V4 ---
'''
    print("[OK] appended bp register v4")
else:
    print("[OK] bp register v4 already present")
W.write_text(s, encoding="utf-8")

# -------------------------
# 3) JS: common v3 add 5-tabs nav + helpers; DataSource add RID selector; Rule Overrides add Apply button
# -------------------------
def write(p: Path, text: str):
    p.write_text(text, encoding="utf-8")
    print("[OK] wrote", p)

common = r'''/* VSP_TABS3_COMMON_V3 (nav + helpers) */
(() => {
  if (window.__vsp_tabs3_v3) return;
  const $ = (s, r=document) => r.querySelector(s);
  const esc = (x)=> (x==null?'':String(x)).replace(/[&<>"']/g, c=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
  async function api(url, opt){
    const r = await fetch(url, opt);
    const t = await r.text();
    let j; try{ j=JSON.parse(t); }catch(e){ j={ok:false, err:"non-json", raw:t.slice(0,800)}; }
    if(!r.ok) throw Object.assign(new Error("HTTP "+r.status), {status:r.status, body:j});
    return j;
  }
  function ensure(){
    if(document.getElementById("vsp_tabs3_v3_style")) return;
    const st=document.createElement("style");
    st.id="vsp_tabs3_v3_style";
    st.textContent=`
      .vsp-nav{display:flex;gap:10px;align-items:center;justify-content:space-between;margin-bottom:12px}
      .vsp-nav-left{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
      .vsp-link{color:#cbd5e1;text-decoration:none;padding:6px 10px;border:1px solid rgba(148,163,184,.18);border-radius:999px;background:#0b1324}
      .vsp-link:hover{border-color:rgba(148,163,184,.45)}
      .vsp-active{border-color:rgba(99,102,241,.65)}
      .vsp-card{background:#0f1b2d;border:1px solid rgba(148,163,184,.18);border-radius:14px;padding:14px}
      .vsp-row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
      .vsp-btn{background:#111c30;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:7px 10px;cursor:pointer}
      .vsp-btn:hover{border-color:rgba(148,163,184,.45)}
      .vsp-in{background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:10px;padding:7px 10px;outline:none}
      .vsp-muted{color:#94a3b8}
      .vsp-badge{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(148,163,184,.22);font-size:12px}
      table.vsp-t{width:100%;border-collapse:separate;border-spacing:0 8px}
      table.vsp-t th{font-weight:600;text-align:left;color:#cbd5e1;font-size:12px;padding:0 10px}
      table.vsp-t td{background:#0b1324;border-top:1px solid rgba(148,163,184,.18);border-bottom:1px solid rgba(148,163,184,.18);padding:10px;font-size:13px;vertical-align:top}
      table.vsp-t tr td:first-child{border-left:1px solid rgba(148,163,184,.18);border-top-left-radius:12px;border-bottom-left-radius:12px}
      table.vsp-t tr td:last-child{border-right:1px solid rgba(148,163,184,.18);border-top-right-radius:12px;border-bottom-right-radius:12px}
      .vsp-code{width:100%;min-height:320px;resize:vertical;font-family:ui-monospace,Menlo,Monaco,Consolas,monospace;background:#0b1324;border:1px solid rgba(148,163,184,.22);color:#e5e7eb;border-radius:12px;padding:12px}
      .vsp-ok{color:#86efac}.vsp-err{color:#fca5a5}
    `;
    document.head.appendChild(st);
  }

  function mountNav(active){
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    const nav = document.createElement("div");
    nav.className = "vsp-nav";
    nav.innerHTML = `
      <div class="vsp-nav-left">
        <a class="vsp-link ${active==='dashboard'?'vsp-active':''}" href="/vsp5">Dashboard</a>
        <a class="vsp-link ${active==='runs'?'vsp-active':''}" href="/runs">Runs & Reports</a>
        <a class="vsp-link ${active==='data_source'?'vsp-active':''}" href="/data_source">Data Source</a>
        <a class="vsp-link ${active==='settings'?'vsp-active':''}" href="/settings">Settings</a>
        <a class="vsp-link ${active==='rule_overrides'?'vsp-active':''}" href="/rule_overrides">Rule Overrides</a>
      </div>
      <div class="vsp-muted" style="font-size:12px">VSP UI</div>
    `;
    root.prepend(nav);
  }

  window.__vsp_tabs3_v3 = { $, esc, api, ensure, mountNav };
})();
'''
write(ROOT/"static/js/vsp_tabs3_common_v3.js", common)

ds = r'''/* VSP Data Source v3 (RID selector) */
(() => {
  if(window.__vsp_ds_v3) return; window.__vsp_ds_v3=true;
  const lib = window.__vsp_tabs3_v3; if(!lib) return;
  const { $, esc, api, ensure, mountNav } = lib;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    mountNav("data_source");

    root.innerHTML += `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Data Source</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Findings table (by RID)</div>
        </div>
        <div class="vsp-row">
          <button class="vsp-btn" id="ds_refresh">Refresh</button>
        </div>
      </div>

      <div class="vsp-card" style="margin-bottom:10px">
        <div class="vsp-row">
          <select class="vsp-in" id="ds_rid" style="min-width:340px"></select>
          <input class="vsp-in" id="ds_q" placeholder="search..." style="flex:1;min-width:220px">
          <select class="vsp-in" id="ds_sev">
            <option value="">Overall: ALL</option>
            <option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option><option>INFO</option><option>TRACE</option>
          </select>
          <input class="vsp-in" id="ds_tool" placeholder="tool (exact)" style="min-width:160px">
          <select class="vsp-in" id="ds_limit">
            <option value="10">10/page</option>
            <option value="20" selected>20/page</option>
            <option value="50">50/page</option>
          </select>
        </div>
        <div class="vsp-muted" id="ds_meta" style="margin-top:8px;font-size:12px"></div>
      </div>

      <div class="vsp-card">
        <table class="vsp-t">
          <thead><tr><th>Severity</th><th>Tool</th><th>Rule</th><th>File</th><th>Line</th><th>Message</th></tr></thead>
          <tbody id="ds_tb"></tbody>
        </table>
        <div class="vsp-row" style="justify-content:flex-end;margin-top:8px">
          <button class="vsp-btn" id="ds_prev">Prev</button>
          <div class="vsp-muted" id="ds_page" style="min-width:110px;text-align:center">1/1</div>
          <button class="vsp-btn" id="ds_next">Next</button>
        </div>
      </div>
    `;

    const st = { offset:0, limit:20, total:0, rid:"" };
    const ridSel=$("#ds_rid"), q=$("#ds_q"), sev=$("#ds_sev"), tool=$("#ds_tool"), lim=$("#ds_limit");
    const tb=$("#ds_tb"), meta=$("#ds_meta"), page=$("#ds_page");

    function debounce(fn, ms=250){ let t=null; return ()=>{ clearTimeout(t); t=setTimeout(fn,ms); }; }

    async function loadRuns(){
      ridSel.innerHTML = `<option value="">(loading runs...)</option>`;
      try{
        const j = await api("/api/ui/runs_v1?limit=160");
        const items = j.items||[];
        if(!items.length){
          ridSel.innerHTML = `<option value="">(no runs found)</option>`;
          return;
        }
        ridSel.innerHTML = items.map(x=>`<option value="${esc(x.rid)}">${esc(x.rid)}</option>`).join("");
        st.rid = ridSel.value || items[0].rid;
        ridSel.value = st.rid;
      }catch(e){
        ridSel.innerHTML = `<option value="">(runs API failed)</option>`;
      }
    }

    async function load(){
      st.limit = parseInt(lim.value||"20",10)||20;
      const url = `/api/ui/findings_v2?rid=${encodeURIComponent(st.rid||"")}&limit=${encodeURIComponent(st.limit)}&offset=${encodeURIComponent(st.offset)}&q=${encodeURIComponent((q.value||"").trim())}&severity=${encodeURIComponent((sev.value||"").trim())}&tool=${encodeURIComponent((tool.value||"").trim().toLowerCase())}`;
      const j = await api(url);
      st.total = j.total||0;
      meta.textContent = `rid: ${j.rid||""} · run_dir: ${j.run_dir||""} · total=${st.total}` + (j.hint?` · hint: ${j.hint}`:"");
      const items = j.items||[];
      tb.innerHTML = items.map(it=>`
        <tr>
          <td><span class="vsp-badge">${esc(it.severity||"")}</span></td>
          <td>${esc(it.tool||"")}</td>
          <td>${esc(it.rule_id||"")}</td>
          <td style="max-width:360px;word-break:break-word">${esc(it.file||"")}</td>
          <td>${esc(it.line||"")}</td>
          <td style="max-width:520px;word-break:break-word">${esc(it.message||"")}</td>
        </tr>`).join("");
      const pages = Math.max(1, Math.ceil((st.total||0)/st.limit));
      const cur = Math.min(pages, Math.floor((st.offset||0)/st.limit)+1);
      page.textContent = `${cur}/${pages}`;
      $("#ds_prev").disabled = (st.offset<=0);
      $("#ds_next").disabled = (st.offset + st.limit >= st.total);
    }

    const reload = debounce(()=>{ st.offset=0; load().catch(console.error); }, 250);
    q.addEventListener("input", reload);
    sev.addEventListener("change", ()=>{ st.offset=0; load().catch(console.error); });
    tool.addEventListener("input", reload);
    lim.addEventListener("change", ()=>{ st.offset=0; load().catch(console.error); });
    ridSel.addEventListener("change", ()=>{ st.rid = ridSel.value||""; st.offset=0; load().catch(console.error); });

    $("#ds_refresh").onclick = ()=>load().catch(console.error);
    $("#ds_prev").onclick = ()=>{ st.offset=Math.max(0, st.offset-st.limit); load().catch(console.error); };
    $("#ds_next").onclick = ()=>{ st.offset=st.offset+st.limit; load().catch(console.error); };

    await loadRuns();
    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
'''
write(ROOT/"static/js/vsp_data_source_tab_v3.js", ds)

stjs = r'''/* VSP Settings v3 (effective mapping) */
(() => {
  if(window.__vsp_st_v3) return; window.__vsp_st_v3=true;
  const lib = window.__vsp_tabs3_v3; if(!lib) return;
  const { $, esc, api, ensure, mountNav } = lib;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    mountNav("settings");

    root.innerHTML += `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Settings</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">UI settings JSON · /api/ui/settings_v2</div>
        </div>
        <div class="vsp-row">
          <button class="vsp-btn" id="st_effective">Show effective</button>
          <button class="vsp-btn" id="st_reload">Reload</button>
          <button class="vsp-btn" id="st_save">Save</button>
        </div>
      </div>
      <div class="vsp-card" style="margin-bottom:10px"><div class="vsp-muted" id="st_meta" style="font-size:12px"></div></div>
      <div class="vsp-card">
        <textarea id="st_text" class="vsp-code" spellcheck="false"></textarea>
        <div id="st_msg" style="margin-top:8px;font-size:12px"></div>
      </div>
    `;

    const meta=$("#st_meta"), txt=$("#st_text"), msg=$("#st_msg");

    async function load(){
      msg.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await api("/api/ui/settings_v2");
      meta.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.settings||{}, null, 2);
      msg.innerHTML = `<span class="vsp-ok">OK</span>`;
    }

    async function save(){
      let obj;
      try{ obj = JSON.parse(txt.value||"{}"); }
      catch(e){ msg.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return; }
      msg.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await api("/api/ui/settings_v2", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({settings:obj})});
      msg.innerHTML = `<span class="vsp-ok">Saved</span> · ${esc(j.path||"")}`;
    }

    async function showEffective(){
      msg.innerHTML = `<span class="vsp-muted">Loading effective...</span>`;
      const j = await api("/api/ui/settings_effective_v1");
      msg.innerHTML = `<span class="vsp-ok">Effective</span>`;
      txt.value = JSON.stringify({settings: JSON.parse(txt.value||"{}"), effective: j.effective}, null, 2);
    }

    $("#st_reload").onclick = ()=>load().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);
    $("#st_save").onclick = ()=>save().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);
    $("#st_effective").onclick = ()=>showEffective().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);

    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
'''
write(ROOT/"static/js/vsp_settings_tab_v3.js", stjs)

rojs = r'''/* VSP Rule Overrides v3 (Apply/Preview) */
(() => {
  if(window.__vsp_ro_v3) return; window.__vsp_ro_v3=true;
  const lib = window.__vsp_tabs3_v3; if(!lib) return;
  const { $, esc, api, ensure, mountNav } = lib;

  async function boot(){
    ensure();
    const root = document.getElementById("vsp_tab_root");
    if(!root) return;
    mountNav("rule_overrides");

    root.innerHTML += `
      <div class="vsp-row" style="justify-content:space-between;margin-bottom:10px">
        <div>
          <div style="font-size:18px;font-weight:800">Rule Overrides</div>
          <div class="vsp-muted" style="font-size:12px;margin-top:2px">Overrides JSON · /api/ui/rule_overrides_v2</div>
        </div>
        <div class="vsp-row">
          <select class="vsp-in" id="ro_rid" style="min-width:320px"></select>
          <button class="vsp-btn" id="ro_apply">Apply to RID</button>
          <button class="vsp-btn" id="ro_reload">Reload</button>
          <button class="vsp-btn" id="ro_save">Save</button>
        </div>
      </div>
      <div class="vsp-card" style="margin-bottom:10px">
        <div class="vsp-muted" id="ro_meta" style="font-size:12px"></div>
        <div class="vsp-muted" style="font-size:12px;margin-top:6px">
          schema: {"rules":[ {"tool":"semgrep","rule_id":"...","action":"ignore|downgrade|upgrade","severity":"LOW","reason":"..."} ]}
        </div>
      </div>
      <div class="vsp-card">
        <textarea id="ro_text" class="vsp-code" spellcheck="false"></textarea>
        <div id="ro_msg" style="margin-top:8px;font-size:12px"></div>
      </div>
    `;

    const ridSel=$("#ro_rid"), meta=$("#ro_meta"), txt=$("#ro_text"), msg=$("#ro_msg");

    function normalize(obj){
      if(Array.isArray(obj)) obj = {rules: obj};
      if(!obj || typeof obj!=="object" || !Array.isArray(obj.rules)) throw new Error("expect {rules:[...]} or [...]");
      return obj;
    }

    async function loadRuns(){
      ridSel.innerHTML = `<option value="">(loading runs...)</option>`;
      try{
        const j = await api("/api/ui/runs_v1?limit=160");
        const items = j.items||[];
        if(!items.length){
          ridSel.innerHTML = `<option value="">(no runs found)</option>`;
          return;
        }
        ridSel.innerHTML = items.map(x=>`<option value="${esc(x.rid)}">${esc(x.rid)}</option>`).join("");
        ridSel.value = items[0].rid;
      }catch(e){
        ridSel.innerHTML = `<option value="">(runs API failed)</option>`;
      }
    }

    async function load(){
      msg.innerHTML = `<span class="vsp-muted">Loading...</span>`;
      const j = await api("/api/ui/rule_overrides_v2");
      meta.textContent = `path: ${j.path||""}`;
      txt.value = JSON.stringify(j.data||{rules:[]}, null, 2);
      msg.innerHTML = `<span class="vsp-ok">OK</span>`;
    }

    async function save(){
      let obj;
      try{ obj = normalize(JSON.parse(txt.value||"{}")); }
      catch(e){ msg.innerHTML = `<span class="vsp-err">Invalid JSON:</span> ${esc(e.message||String(e))}`; return; }
      msg.innerHTML = `<span class="vsp-muted">Saving...</span>`;
      const j = await api("/api/ui/rule_overrides_v2", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(obj)});
      msg.innerHTML = `<span class="vsp-ok">Saved</span> · rules_n=${esc(j.rules_n||"")}`;
      await load();
    }

    async function apply(){
      const rid = (ridSel.value||"").trim();
      if(!rid){ msg.innerHTML = `<span class="vsp-err">No RID selected</span>`; return; }
      msg.innerHTML = `<span class="vsp-muted">Applying overrides...</span>`;
      const j = await api(`/api/ui/rule_overrides_apply_v1?rid=${encodeURIComponent(rid)}`);
      msg.innerHTML = `<span class="vsp-ok">Applied</span> · ignored=${esc(j.stats?.ignored)} downgraded=${esc(j.stats?.downgraded)} upgraded=${esc(j.stats?.upgraded)} · out=${esc(j.out_fp||"")}`;
    }

    $("#ro_reload").onclick = ()=>load().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);
    $("#ro_save").onclick = ()=>save().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);
    $("#ro_apply").onclick = ()=>apply().catch(e=>msg.innerHTML=`<span class="vsp-err">${esc(e.message||e)}</span>`);

    await loadRuns();
    await load();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
'''
write(ROOT/"static/js/vsp_rule_overrides_tab_v3.js", rojs)

# -------------------------
# 4) Minimal templates stay minimal, but now include nav and v3 scripts only (already)
# -------------------------
def write_min(p: Path, title: str, tab: str, js_common: str, js_tab: str):
    ts=int(time.time())
    html = f'''<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>{title}</title>
  <link rel="stylesheet" href="/static/css/vsp_dark_commercial_p1_2.css"/>
  <style id="VSP_TABS3_FORCE_DARK_BG_V1">html,body{{background:#070e1a;color:#e5e7eb;margin:0;}}</style>
</head>
<body>
  <div id="vsp_tab_root" data-vsp-tab="{tab}" style="padding:16px"><div style="color:#94a3b8;font-size:12px">Loading...</div></div>
  <script src="/{js_common}?v={ts}"></script>
  <script src="/{js_tab}?v={ts}"></script>
</body>
</html>
'''
    p.write_text(html, encoding="utf-8")

tpls = [
  (ROOT/"templates/vsp_data_source_2025.html", "VSP • Data Source", "data_source",
   "static/js/vsp_tabs3_common_v3.js", "static/js/vsp_data_source_tab_v3.js"),
  (ROOT/"templates/vsp_settings_2025.html", "VSP • Settings", "settings",
   "static/js/vsp_tabs3_common_v3.js", "static/js/vsp_settings_tab_v3.js"),
  (ROOT/"templates/vsp_rule_overrides_2025.html", "VSP • Rule Overrides", "rule_overrides",
   "static/js/vsp_tabs3_common_v3.js", "static/js/vsp_rule_overrides_tab_v3.js"),
]
stamp=time.strftime("%Y%m%d_%H%M%S")
for p, title, tab, cjs, tjs in tpls:
    if not p.exists():
        print("[ERR] missing", p); continue
    bak = p.with_name(p.name + f".bak_min_v4_{stamp}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    write_min(p, title, tab, cjs, tjs)
    print("[OK] rewrote minimal", p)

# -------------------------
# 5) Settings env export script + patch runner scripts (best-effort)
# -------------------------
env_sh = ROOT/"bin/vsp_settings_env_export_v1.sh"
env_sh.write_text(r'''#!/usr/bin/env bash
# VSP_SETTINGS_ENV_EXPORT_V1
set -euo pipefail

UI_ROOT="${VSP_UI_ROOT:-/home/test/Data/SECURITY_BUNDLE/ui}"
SETTINGS="${UI_ROOT}/out_ci/vsp_settings_v2/settings.json"

# defaults
VSP_TIMEOUT_KICS_SEC="${VSP_TIMEOUT_KICS_SEC:-900}"
VSP_TIMEOUT_CODEQL_SEC="${VSP_TIMEOUT_CODEQL_SEC:-1800}"
VSP_TIMEOUT_TRIVY_SEC="${VSP_TIMEOUT_TRIVY_SEC:-900}"
VSP_DEGRADE_GRACEFUL="${VSP_DEGRADE_GRACEFUL:-true}"

if [ -s "$SETTINGS" ]; then
  # read via python (no jq dependency)
  read -r VSP_TIMEOUT_KICS_SEC VSP_TIMEOUT_CODEQL_SEC VSP_TIMEOUT_TRIVY_SEC VSP_DEGRADE_GRACEFUL < <(
    python3 - <<'PY'
import json, sys
p=sys.argv[1]
try:
    s=json.load(open(p,'r',encoding='utf-8'))
except Exception:
    s={}
t=s.get("timeouts") if isinstance(s.get("timeouts"), dict) else {}
def geti(k, d):
    try: return int(t.get(k, d))
    except Exception: return d
k=geti("kics_sec", 900)
c=geti("codeql_sec", 1800)
tr=geti("trivy_sec", 900)
dg=s.get("degrade_graceful", True)
dg = "true" if (dg is True or str(dg).strip().lower() not in ("0","false","no","off")) else "false"
print(k, c, tr, dg)
PY
"$SETTINGS"
  )
fi

export VSP_TIMEOUT_KICS_SEC VSP_TIMEOUT_CODEQL_SEC VSP_TIMEOUT_TRIVY_SEC VSP_DEGRADE_GRACEFUL
''', encoding="utf-8")
env_sh.chmod(0o755)
print("[OK] wrote", env_sh)

# patch runner scripts if exist
candidates=[]
for pat in ("run_all.sh","run_all_tools_v2.sh","run_all_tools_v*.sh","run_kics_v2.sh","run_codeql*.sh"):
    candidates += list((ROOT/"bin").glob(pat))
patch_marker="VSP_SETTINGS_SOURCE_V1"
for f in candidates:
    try:
        s=f.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if patch_marker in s: 
        print("[OK] runner already patched:", f.name)
        continue
    ins = r'''
# --- VSP_SETTINGS_SOURCE_V1 ---
if [ -f "$(dirname "$0")/vsp_settings_env_export_v1.sh" ]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/vsp_settings_env_export_v1.sh" || true
fi
# --- /VSP_SETTINGS_SOURCE_V1 ---
'''
    # inject after shebang
    if s.startswith("#!"):
        lines=s.splitlines(True)
        lines.insert(1, ins+"\n")
        s2="".join(lines)
    else:
        s2=ins+"\n"+s
    bak=f.with_name(f.name+f".bak_settings_{stamp}")
    bak.write_text(s, encoding="utf-8")
    f.write_text(s2, encoding="utf-8")
    print("[OK] patched runner to source settings:", f.name)

print("[DONE] tabs3 bundle v4 patched")
PY

echo "== py_compile =="
python3 -m py_compile vsp_tabs3_ui_bp_v4.py wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2

echo "== quick verify endpoints =="
curl -fsS "http://127.0.0.1:8910/api/ui/runs_v1?limit=3" | head -c 240; echo
curl -fsS "http://127.0.0.1:8910/api/ui/findings_v2?limit=1&offset=0" | head -c 240; echo
curl -fsS "http://127.0.0.1:8910/api/ui/settings_effective_v1" | head -c 240; echo
curl -fsS "http://127.0.0.1:8910/api/ui/rule_overrides_v2" | head -c 240; echo

echo "[OK] bundle commercialize v1 done"
