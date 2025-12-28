# -*- coding: utf-8 -*-
from __future__ import annotations
from flask import Blueprint, jsonify, request
from pathlib import Path
import os, json, time

vsp_tabs3_ui_bp_v3 = Blueprint("vsp_tabs3_ui_bp_v3", __name__)

def _now(): return int(time.time())

def _ui_root() -> Path:
    return Path(os.environ.get("VSP_UI_ROOT", str(Path.cwd()))).resolve()

def _out_candidates():
    env = os.environ.get("SECURITY_BUNDLE_OUT") or os.environ.get("VSP_OUT_DIR")
    if env: return [Path(env)]
    return [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]

def _latest_findings_json():
    roots = [p for p in _out_candidates() if p.exists()]
    run_dirs = []
    for r in roots:
        for d in r.glob("RUN_*"):
            if d.is_dir(): run_dirs.append(d)
        for d in r.glob("**/RUN_*"):
            if d.is_dir(): run_dirs.append(d)
    run_dirs = sorted(set(run_dirs), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)

    rels = [Path("reports/findings_unified.json"), Path("findings_unified.json"), Path("findings/findings_unified.json")]
    for d in run_dirs[:250]:
        for rel in rels:
            fp = d/rel
            if fp.exists(): return str(d), fp
    return None, None

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
    }

def _counts(items):
    c = {k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}
    for it in items: c[_norm_sev(it.get("severity"))] += 1
    c["TOTAL"] = sum(c.values())
    return c

@vsp_tabs3_ui_bp_v3.get("/api/ui/findings_v2")
def api_ui_findings_v2():
    limit = int(request.args.get("limit","20") or 20)
    offset = int(request.args.get("offset","0") or 0)
    q = (request.args.get("q") or "").strip().lower()
    sev = (request.args.get("severity") or "").strip().upper()
    tool = (request.args.get("tool") or "").strip().lower()

    run_dir, fp = _latest_findings_json()
    if not fp or not fp.exists():
        return jsonify({"ok": True, "items": [], "total": 0, "counts": _counts([]), "run_dir": None, "ts": _now()})

    try:
        data = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        data = []

    if isinstance(data, dict):
        for k in ("items","findings","results","rows"):
            if isinstance(data.get(k), list):
                data = data[k]; break
    if not isinstance(data, list): data = []

    rows = [_row(x) for x in data if isinstance(x, dict)]

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
    return jsonify({"ok": True, "items": items, "total": total, "counts": counts, "run_dir": run_dir, "ts": _now(),
                    "limit": limit, "offset": offset, "q": q, "severity": sev, "tool": tool})

def _state_dir(name):
    d = _ui_root()/"out_ci"/name
    d.mkdir(parents=True, exist_ok=True)
    return d

@vsp_tabs3_ui_bp_v3.get("/api/ui/settings_v2")
def api_ui_settings_get_v2():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    try:
        settings = json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else {}
    except Exception:
        settings = {}
    return jsonify({"ok": True, "settings": settings, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v3.post("/api/ui/settings_v2")
def api_ui_settings_set_v2():
    p = _state_dir("vsp_settings_v2")/"settings.json"
    body = request.get_json(silent=True) or {}
    settings = body.get("settings", body)
    if not isinstance(settings, dict):
        return jsonify({"ok": False, "err": "settings must be object"}), 400
    p.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    return jsonify({"ok": True, "path": str(p), "ts": _now()})

@vsp_tabs3_ui_bp_v3.get("/api/ui/rule_overrides_v2")
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

@vsp_tabs3_ui_bp_v3.post("/api/ui/rule_overrides_v2")
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
