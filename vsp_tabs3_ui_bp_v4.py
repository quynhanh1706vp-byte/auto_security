# -*- coding: utf-8 -*-
from __future__ import annotations
from flask import Blueprint, jsonify, request
from pathlib import Path
import os, json, time

vsp_tabs3_ui_bp_v4 = Blueprint("vsp_tabs3_ui_bp_v4", __name__)

def _now(): return int(time.time())

def _ui_root() -> Path:
    return Path(os.environ.get("VSP_UI_ROOT", str(Path.cwd()))).resolve()

def _state_dir(name: str) -> Path:
    d = _ui_root() / "out_ci" / name
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
    out=[]
    for r in roots:
        if r and r.exists():
            rp = r.resolve()
            if rp not in out: out.append(rp)
    return out

def _scan_run_dirs(limit=600):
    run_dirs=[]
    for r in _out_roots():
        for d in r.glob("RUN_*"):
            if d.is_dir(): run_dirs.append(d)
        for d in r.glob("**/RUN_*"):
            if d.is_dir(): run_dirs.append(d)

    uniq={}
    for d in run_dirs:
        try:
            uniq[str(d.resolve())]=d.resolve()
        except Exception:
            uniq[str(d)]=d
    run_dirs=list(uniq.values())
    run_dirs.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return run_dirs[:limit]

def _latest_run_dir():
    xs=_scan_run_dirs(limit=1)
    return xs[0] if xs else None

def _find_run_dir_by_rid(rid: str):
    rid=(rid or "").strip().lower()
    if not rid: return None
    for d in _scan_run_dirs(limit=1200):
        if rid in d.name.lower():
            return d
    return None

def _latest_findings_fp(run_dir: Path):
    rels = [
        Path("reports/findings_unified.json"),
        Path("findings_unified.json"),
        Path("findings/findings_unified.json"),
    ]
    for rel in rels:
        fp=run_dir/rel
        if fp.exists(): return fp
    return None

def _load_findings(fp: Path):
    try:
        data=json.loads(fp.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return []
    if isinstance(data, dict):
        for k in ("items","findings","results","rows"):
            if isinstance(data.get(k), list):
                return data[k]
    return data if isinstance(data, list) else []

def _norm_sev(x):
    x=str(x or "").strip().upper()
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
    }

def _counts(items):
    c = {k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}
    for it in items:
        c[_norm_sev(it.get("severity"))]+=1
    c["TOTAL"]=sum(c.values())
    return c

@vsp_tabs3_ui_bp_v4.get("/api/ui/runs_v1")
def api_ui_runs_v1():
    limit=int(request.args.get("limit","120") or 120)
    items=[]
    for d in _scan_run_dirs(limit=max(60, min(2000, limit))):
        try:
            items.append({"rid": d.name, "run_dir": str(d), "mtime": int(d.stat().st_mtime)})
        except Exception:
            items.append({"rid": d.name, "run_dir": str(d), "mtime": 0})
    return jsonify({"ok": True, "items": items[:limit], "total": len(items), "ts": _now()})

@vsp_tabs3_ui_bp_v4.get("/api/ui/findings_v2")
def api_ui_findings_v2():
    limit=int(request.args.get("limit","20") or 20)
    offset=int(request.args.get("offset","0") or 0)
    q=(request.args.get("q") or "").strip().lower()
    sev=(request.args.get("severity") or "").strip().upper()
    tool=(request.args.get("tool") or "").strip().lower()
    rid=(request.args.get("rid") or "").strip()

    run_dir=_find_run_dir_by_rid(rid) if rid else _latest_run_dir()
    if not run_dir:
        return jsonify({"ok": True, "items": [], "total": 0, "counts": _counts([]),
                        "rid": rid or None, "run_dir": None, "hint": "no RUN_* directories found", "ts": _now()})

    fp=_latest_findings_fp(run_dir)
    if not fp:
        return jsonify({"ok": True, "items": [], "total": 0, "counts": _counts([]),
                        "rid": rid or run_dir.name, "run_dir": str(run_dir),
                        "hint": "no findings_unified.json found", "ts": _now()})

    raw=_load_findings(fp)
    rows=[_row(x) for x in raw if isinstance(x, dict)]

    def ok(it):
        if sev and _norm_sev(it.get("severity"))!=sev: return False
        if tool and (it.get("tool","").lower()!=tool): return False
        if q:
            hay=" ".join([str(it.get(k,"")) for k in ("tool","rule_id","message","file")]).lower()
            if q not in hay: return False
        return True

    rows=[r for r in rows if ok(r)]
    total=len(rows)
    counts=_counts(rows)
    rank={"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3,"INFO":4,"TRACE":5}
    rows.sort(key=lambda r:(rank.get(_norm_sev(r.get("severity")),9), r.get("tool",""), r.get("rule_id","")))
    items=rows[offset:offset+limit]
    return jsonify({"ok": True, "items": items, "total": total, "counts": counts,
                    "rid": rid or run_dir.name, "run_dir": str(run_dir), "fp": str(fp),
                    "limit": limit, "offset": offset, "q": q, "severity": sev, "tool": tool, "ts": _now()})

def _load_rules():
    p=_state_dir("rule_overrides_v2")/"rules.json"
    try:
        data=json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {"rules":[]}
    except Exception:
        data={"rules":[]}
    if isinstance(data, list): data={"rules": data}
    if not isinstance(data, dict): data={"rules":[]}
    if not isinstance(data.get("rules"), list): data["rules"]=[]
    return p, data

def _key(tool, rule_id):
    return (str(tool).strip().lower()+"::"+str(rule_id).strip()).strip()

def _apply(findings, rules):
    m={}
    for r in rules:
        if not isinstance(r, dict): continue
        tool=str(r.get("tool","")).strip()
        rule_id=str(r.get("rule_id","")).strip()
        if tool and rule_id:
            m[_key(tool, rule_id)] = r

    out=[]
    stats={"ignored":0,"downgraded":0,"upgraded":0,"touched":0}
    for f in findings:
        if not isinstance(f, dict): continue
        tool=str(f.get("tool") or f.get("scanner") or f.get("engine") or "unknown")
        rule_id=str(f.get("rule_id") or f.get("rule") or f.get("check_id") or f.get("id") or "")
        r=m.get(_key(tool, rule_id))
        if not r:
            out.append(f); continue
        action=str(r.get("action","")).strip().lower()
        stats["touched"]+=1
        if action=="ignore":
            stats["ignored"]+=1
            continue
        sev_new=r.get("severity")
        sev_new=_norm_sev(sev_new) if sev_new else None
        g=dict(f)
        g["override"]={"action":action,"severity":sev_new,"reason":str(r.get("reason",""))[:500],"ts":_now()}
        if action in ("downgrade","upgrade") and sev_new:
            old=_norm_sev(g.get("severity") or g.get("sev") or g.get("level"))
            g["severity"]=sev_new
            g["override"]["from"]=old
            if action=="downgrade": stats["downgraded"]+=1
            else: stats["upgraded"]+=1
        out.append(g)
    return out, stats

@vsp_tabs3_ui_bp_v4.get("/api/ui/rule_overrides_apply_v1")
def api_rule_apply():
    rid=(request.args.get("rid") or "").strip()
    run_dir=_find_run_dir_by_rid(rid) if rid else _latest_run_dir()
    if not run_dir:
        return jsonify({"ok": False, "err":"no RUN_* dirs", "rid": rid or None, "ts": _now()}), 404
    fp=_latest_findings_fp(run_dir)
    if not fp:
        return jsonify({"ok": False, "err":"no findings_unified.json", "run_dir": str(run_dir), "rid": rid or run_dir.name, "ts": _now()}), 404
    rules_fp, rules_data=_load_rules()
    rules=rules_data.get("rules", [])
    findings=_load_findings(fp)
    applied, stats=_apply(findings, rules)

    out_fp=run_dir/"reports"/"findings_unified_overridden.json"
    out_fp.parent.mkdir(parents=True, exist_ok=True)
    out_fp.write_text(json.dumps({"items": applied, "meta": {
        "rid": rid or run_dir.name, "run_dir": str(run_dir),
        "source_fp": str(fp), "rules_fp": str(rules_fp),
        "stats": stats, "ts": _now()
    }}, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "rid": rid or run_dir.name, "run_dir": str(run_dir),
                    "source_fp": str(fp), "rules_fp": str(rules_fp), "out_fp": str(out_fp),
                    "stats": stats, "rules_n": len(rules), "ts": _now()})

@vsp_tabs3_ui_bp_v4.get("/api/ui/settings_v2")
def api_settings_get():
    p=_state_dir("vsp_settings_v2")/"settings.json"
    try:
        settings=json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {}
    except Exception:
        settings={}
    return jsonify({"ok": True, "settings": settings, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v4.post("/api/ui/settings_v2")
def api_settings_set():
    p=_state_dir("vsp_settings_v2")/"settings.json"
    body=request.get_json(silent=True) or {}
    settings=body.get("settings", body)
    if not isinstance(settings, dict):
        return jsonify({"ok": False, "err":"settings must be object"}), 400
    p.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "ts": _now()})

def _settings_effective(settings: dict):
    timeouts=settings.get("timeouts") if isinstance(settings.get("timeouts"), dict) else {}
    tools_enabled=settings.get("tools_enabled") if isinstance(settings.get("tools_enabled"), dict) else {}
    degrade=settings.get("degrade_graceful", True)

    def geti(k, d):
        try: return int(timeouts.get(k, d))
        except Exception: return d

    eff={
        "degrade_graceful": bool(degrade),
        "timeouts":{"kics_sec": geti("kics_sec",900), "codeql_sec": geti("codeql_sec",1800), "trivy_sec": geti("trivy_sec",900)},
        "tools_enabled": {}
    }
    default_tools=["bandit","semgrep","gitleaks","kics","trivy","syft","grype","codeql"]
    for t in default_tools:
        v=tools_enabled.get(t, True)
        eff["tools_enabled"][t] = bool(v) if isinstance(v,(bool,int)) else (str(v).strip().lower() not in ("0","false","no","off"))
    return eff

@vsp_tabs3_ui_bp_v4.get("/api/ui/settings_effective_v1")
def api_settings_effective():
    p=_state_dir("vsp_settings_v2")/"settings.json"
    try:
        settings=json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {}
    except Exception:
        settings={}
    return jsonify({"ok": True, "effective": _settings_effective(settings), "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v4.get("/api/ui/rule_overrides_v2")
def api_rules_get():
    p=_state_dir("rule_overrides_v2")/"rules.json"
    try:
        data=json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {"rules":[]}
    except Exception:
        data={"rules":[]}
    if isinstance(data, list): data={"rules": data}
    if not isinstance(data, dict): data={"rules":[]}
    if not isinstance(data.get("rules"), list): data["rules"]=[]
    return jsonify({"ok": True, "data": data, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v4.post("/api/ui/rule_overrides_v2")
def api_rules_set():
    p=_state_dir("rule_overrides_v2")/"rules.json"
    body=request.get_json(silent=True) or {}
    data=body.get("data", body)
    if isinstance(data, list): data={"rules": data}
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        return jsonify({"ok": False, "err":"expect {rules:[...]} or [...]"}), 400
    out={"rules":[r for r in data["rules"] if isinstance(r, dict)], "updated_ts": _now()}
    p.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "rules_n": len(out["rules"]), "ts": _now()})
