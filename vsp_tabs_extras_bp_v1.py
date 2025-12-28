# -*- coding: utf-8 -*-
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
