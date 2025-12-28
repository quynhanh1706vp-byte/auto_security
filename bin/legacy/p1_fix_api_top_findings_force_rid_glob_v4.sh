#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_glob_v4_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_glob_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_API_TOP_FINDINGS_FORCE_RID_GLOB_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r"""
# ===== VSP_P1_API_TOP_FINDINGS_FORCE_RID_GLOB_V4 =====
# Commercial fix: always honor ?rid=... for /api/vsp/top_findings_v1 (no implicit rid_latest override).
# Implementation reads findings_unified.json by rid via glob search in common run roots.

def _vsp__topfind_v4__severity_rank(sev: str) -> int:
    sev = (sev or "").upper().strip()
    order = {"CRITICAL": 50, "HIGH": 40, "MEDIUM": 30, "LOW": 20, "INFO": 10, "TRACE": 0}
    return order.get(sev, 0)

def _vsp__topfind_v4__now_iso():
    try:
        import datetime
        return datetime.datetime.utcnow().isoformat(timespec="microseconds") + "Z"
    except Exception:
        return ""

def _vsp__topfind_v4__find_file_for_rid(rid: str):
    import os, glob

    rid = (rid or "").strip()
    if not rid:
        return None, []

    roots = []
    # allow override via env
    env_root = os.environ.get("VSP_RUNS_ROOT") or os.environ.get("VSP_OUT_ROOT") or ""
    if env_root.strip():
        roots.append(env_root.strip())

    # common roots (keep stable for your layout)
    roots += [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    ]

    # de-dup
    roots2 = []
    for r in roots:
        if r and r not in roots2:
            roots2.append(r)
    roots = roots2

    subs = [
        "reports/findings_unified.json",
        "report/findings_unified.json",
        "findings_unified.json",
        "reports/findings_unified.jsonl",
        "report/findings_unified.jsonl",
    ]

    tried = []
    cand = []

    for root in roots:
        # exact rid folder
        for sub in subs:
            pat = os.path.join(root, rid, sub)
            tried.append(pat)
            cand += glob.glob(pat)

        # rid prefix folders (some pipelines add suffix)
        for sub in subs:
            pat = os.path.join(root, f"{rid}*", sub)
            tried.append(pat)
            cand += glob.glob(pat)

    # choose newest by mtime
    cand = [c for c in cand if c and os.path.isfile(c)]
    if not cand:
        return None, tried
    cand.sort(key=lambda x: os.path.getmtime(x), reverse=True)
    return cand[0], tried

def _vsp__topfind_v4__load_findings(path: str):
    import json
    from pathlib import Path

    if not path:
        return []
    fp = Path(path)
    if not fp.exists():
        return []

    # support json / jsonl (best-effort)
    if fp.suffix.lower() == ".jsonl":
        out = []
        try:
            for line in fp.read_text(encoding="utf-8", errors="replace").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except Exception:
                    continue
            return out
        except Exception:
            return []

    try:
        data = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return []

    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for k in ("findings", "items", "results", "data"):
            v = data.get(k)
            if isinstance(v, list):
                return v
    return []

def _vsp__topfind_v4__normalize_item(x):
    # keep fields that UI expects; strip internal file paths already blanked by your earlier policies
    if not isinstance(x, dict):
        return None
    return {
        "tool": (x.get("tool") or "").strip() or None,
        "severity": (x.get("severity") or "").strip() or None,
        "title": (x.get("title") or "").strip() or None,
        "component": (x.get("component") or "").strip() or None,
        "version": (x.get("version") or "").strip() or None,
        "cwe": x.get("cwe"),
        "rule_id": (x.get("rule_id") or "").strip() or None,
        "file": (x.get("file") or "").strip() or "",   # keep empty if sanitized
        "line": x.get("line"),
    }

def _vsp__topfind_v4__handler():
    from flask import request, jsonify
    rid_req = (request.args.get("rid") or "").strip()
    if rid_req in ("YOUR_RID", "null", "undefined"):
        rid_req = ""

    # IMPORTANT: If user supplies rid => honor it; do NOT override to rid_latest.
    rid_used = rid_req

    # limit
    try:
        limit = int(request.args.get("limit") or "20")
    except Exception:
        limit = 20
    if limit < 1:
        limit = 1
    if limit > 2500:
        limit = 2500

    if not rid_used:
        # no rid given => we allow "latest" behavior if you want; keep minimal and explicit
        try:
            # try to reuse existing helper if present
            fn = globals().get("api_vsp_rid_latest") or globals().get("rid_latest") or None
            if callable(fn):
                j = fn()
                # jsonify response -> dict? best effort
        except Exception:
            pass
        # fallback: keep empty
        return jsonify({
            "ok": True,
            "rid": "",
            "rid_requested": rid_req,
            "rid_used": "",
            "total": 0,
            "limit_applied": limit,
            "items_truncated": False,
            "items": [],
            "from": None,
            "reason": "rid is required (provide ?rid=RID).",
            "err": "",
            "has": [],
            "ts": _vsp__topfind_v4__now_iso(),
        })

    path, tried = _vsp__topfind_v4__find_file_for_rid(rid_used)
    if not path:
        return jsonify({
            "ok": True,
            "rid": rid_used,
            "rid_requested": rid_req,
            "rid_used": rid_used,
            "total": 0,
            "limit_applied": limit,
            "items_truncated": False,
            "items": [],
            "from": None,
            "reason": "no findings_unified.json found for rid (degraded).",
            "err": "",
            "tried": tried[:40],  # avoid giant payload
            "has": [],
            "ts": _vsp__topfind_v4__now_iso(),
        })

    findings = _vsp__topfind_v4__load_findings(path)
    items = []
    for x in findings:
        it = _vsp__topfind_v4__normalize_item(x)
        if it:
            items.append(it)

    # sort strongest first (severity, then tool/title)
    items.sort(key=lambda it: (
        -_vsp__topfind_v4__severity_rank(it.get("severity") or ""),
        (it.get("tool") or ""),
        (it.get("title") or ""),
    ))

    total = len(items)
    truncated = total > limit
    items = items[:limit]

    return jsonify({
        "ok": True,
        "rid": rid_used,
        "rid_requested": rid_req,
        "rid_used": rid_used,
        "total": total,
        "limit_applied": limit,
        "items_truncated": truncated,
        "items": items,
        "from": path,
        "reason": None,
        "err": "",
        "has": ["json:findings_unified.json"],
        "ts": _vsp__topfind_v4__now_iso(),
    })

def _vsp__topfind_v4__install():
    # Replace all endpoints bound to /api/vsp/top_findings_v1
    try:
        rules = [r for r in app.url_map.iter_rules() if getattr(r, "rule", "") == "/api/vsp/top_findings_v1"]
        for r in rules:
            if r.endpoint in app.view_functions:
                app.view_functions[r.endpoint] = _vsp__topfind_v4__handler
        return len(rules)
    except Exception:
        return 0

try:
    _n = _vsp__topfind_v4__install()
except Exception:
    _n = 0
# ===== END VSP_P1_API_TOP_FINDINGS_FORCE_RID_GLOB_V4 =====
"""

# Append near end
s2 = s + "\n" + block + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile PASS"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted: $SVC"
else
  echo "[WARN] systemctl not found; restart your server manually"
fi

echo
echo "== [TEST] rid must be honored (rid_used == rid_requested) =="
RID_TEST="${1:-VSP_CI_20251218_114312}"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=3&rid=$RID_TEST" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"rid_requested=",j.get("rid_requested"),"rid_used=",j.get("rid_used"),"items_len=",len(j.get("items") or []),"from=",j.get("from"))'
