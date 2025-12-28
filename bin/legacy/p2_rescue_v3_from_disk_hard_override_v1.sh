#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_rescue_v3_disk_${TS}"
echo "[OK] backup: ${APP}.bak_rescue_v3_disk_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Disable old patch blocks that can recurse/crash
blocks = [
  ("# ===== VSP_AFTER_REQUEST_CONTRACTIZE_V1 =====", "# ===== /VSP_AFTER_REQUEST_CONTRACTIZE_V1 ====="),
  ("# ===== VSP_AFTER_REQUEST_CONTRACTIZE_V2 =====", "# ===== /VSP_AFTER_REQUEST_CONTRACTIZE_V2 ====="),
  ("# ===== VSP_BRIDGE_V3_FROM_V1_FILL_V1 =====", "# ===== /VSP_BRIDGE_V3_FROM_V1_FILL_V1 ====="),
  ("# ===== VSP_BRIDGE_V3_FROM_V1_TESTCLIENT_V2 =====", "# ===== /VSP_BRIDGE_V3_FROM_V1_TESTCLIENT_V2 ====="),
  ("# ===== VSP_FILL_V3_FROM_RUN_FILE_ALLOW_V3P1 =====", "# ===== /VSP_FILL_V3_FROM_RUN_FILE_ALLOW_V3P1 ====="),
  ("# ===== VSP_V3_BEFORE_REQUEST_OVERRIDE_V1 =====", "# ===== /VSP_V3_BEFORE_REQUEST_OVERRIDE_V1 ====="),
]

def disable_block(txt, b, e):
    if b not in txt or e not in txt:
        return txt, False
    pat = re.compile(re.escape(b) + r".*?" + re.escape(e), re.S)
    repl = b + "\n# [DISABLED] replaced by VSP_V3_FROM_DISK_OVERRIDE_V2\n" + e
    return pat.sub(repl, txt, count=1), True

changed = 0
for b,e in blocks:
    s, did = disable_block(s, b, e)
    changed += 1 if did else 0

# 2) Append a single safe override that reads findings_unified.json from disk (no recursion)
tag_b = "# ===== VSP_V3_FROM_DISK_OVERRIDE_V2 ====="
tag_e = "# ===== /VSP_V3_FROM_DISK_OVERRIDE_V2 ====="
if tag_b in s and tag_e in s:
    print("[OK] disk override V2 already present")
else:
    patch = r"""

# ===== VSP_V3_FROM_DISK_OVERRIDE_V2 =====
# Commercial: stable V3 endpoints without recursion.
# Reads findings_unified.json directly from disk by RID, caches per-process.

try:
    import os, json, glob, time
except Exception:
    os = None; json = None; glob = None; time = None

try:
    from flask import request, jsonify
except Exception:
    request = None
    jsonify = None

_VSP_DISK_CACHE = {}  # rid -> {"path": str, "mtime": float, "findings": list, "sev": dict, "total": int, "ts": float}

def _vsp_norm_sev_v2(d=None):
    d = d if isinstance(d, dict) else {}
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        d.setdefault(k, 0)
    return d

def _vsp_pick_rid_v2():
    try:
        rid = (request.args.get("rid") or "").strip()
    except Exception:
        rid = ""
    if rid:
        return rid
    # fallback: try existing rid_latest handler if exists via local env var or simple file; keep empty if not
    return ""

def _vsp_guess_paths_for_rid(rid: str):
    # Fast direct guesses first (no recursive scan)
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE",
    ]
    rels = [
        "reports/findings_unified.json",
        "report/findings_unified.json",
        "findings_unified.json",
        "reports/findings.json",
        "report/findings.json",
    ]
    cand = []
    for r in roots:
        for rel in rels:
            cand.append(os.path.join(r, rid, rel))
    return cand

def _vsp_find_findings_file(rid: str):
    if os is None:
        return None
    # 1) direct
    for c in _vsp_guess_paths_for_rid(rid):
        if os.path.isfile(c):
            return c
    # 2) limited glob fallback (still bounded)
    if glob is None:
        return None
    patterns = [
        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/reports/findings_unified.json",
        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/report/findings_unified.json",
        f"/home/test/Data/SECURITY_BUNDLE/**/{rid}/findings_unified.json",
    ]
    for pat in patterns:
        hits = glob.glob(pat, recursive=True)
        if hits:
            hits.sort(key=lambda x: len(x))
            return hits[0]
    return None

def _vsp_load_findings_cached(rid: str):
    if json is None or os is None or time is None:
        return ([], _vsp_norm_sev_v2({}), 0, None)

    now = time.time()
    ent = _VSP_DISK_CACHE.get(rid)
    if ent and (now - ent.get("ts", 0) < 8.0):  # small TTL to reduce IO
        return (ent.get("findings") or [], ent.get("sev") or _vsp_norm_sev_v2({}), int(ent.get("total") or 0), ent.get("path"))

    path = ent.get("path") if ent else None
    if not path or not os.path.isfile(path):
        path = _vsp_find_findings_file(rid)

    if not path or not os.path.isfile(path):
        _VSP_DISK_CACHE[rid] = {"path": None, "mtime": 0, "findings": [], "sev": _vsp_norm_sev_v2({}), "total": 0, "ts": now}
        return ([], _vsp_norm_sev_v2({}), 0, None)

    try:
        mtime = os.path.getmtime(path)
    except Exception:
        mtime = 0

    if ent and ent.get("path") == path and ent.get("mtime") == mtime and ent.get("findings") is not None:
        ent["ts"] = now
        return (ent.get("findings") or [], ent.get("sev") or _vsp_norm_sev_v2({}), int(ent.get("total") or 0), path)

    # load
    try:
        raw = json.load(open(path, "r", encoding="utf-8"))
    except Exception:
        raw = None

    findings = []
    if isinstance(raw, dict):
        findings = raw.get("findings") or raw.get("items") or []
    elif isinstance(raw, list):
        findings = raw
    if not isinstance(findings, list):
        findings = []

    sev = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}
    for it in findings:
        if not isinstance(it, dict): 
            continue
        sv = (it.get("severity") or it.get("sev") or it.get("level") or "").upper()
        if sv in sev:
            sev[sv] += 1
        else:
            # map common
            if sv == "WARNING": sev["LOW"] += 1
            elif sv == "ERROR": sev["HIGH"] += 1

    total = len(findings)
    _VSP_DISK_CACHE[rid] = {"path": path, "mtime": mtime, "findings": findings, "sev": _vsp_norm_sev_v2(sev), "total": total, "ts": now}
    return (findings, _vsp_norm_sev_v2(sev), total, path)

def _vsp_get_limit_offset():
    try:
        lim = int(request.args.get("limit") or 50)
    except Exception:
        lim = 50
    try:
        off = int(request.args.get("offset") or 0)
    except Exception:
        off = 0
    if lim <= 0: lim = 50
    if lim > 200: lim = 200
    if off < 0: off = 0
    return lim, off

def _vsp_override_v3_if_match():
    if request is None or jsonify is None:
        return None
    path = (request.path or "")
    if path not in ("/api/vsp/findings_page_v3", "/api/vsp/findings_v3", "/api/vsp/dashboard_v3", "/api/vsp/run_gate_v3"):
        return None

    rid = _vsp_pick_rid_v2()
    lim, off = _vsp_get_limit_offset()
    findings, sev, total, fpath = _vsp_load_findings_cached(rid)

    if path in ("/api/vsp/findings_page_v3", "/api/vsp/findings_v3"):
        items = findings[off:off+lim] if off else findings[:lim]
        return jsonify(ok=True, rid=rid, items=items, total=int(total), sev=sev, total_findings=int(total),
                       from_path=fpath, limit=lim, offset=off)

    # dashboard / run_gate: provide kpis + sev + total_findings
    kpis = {
        "rid": rid,
        "critical": int(sev.get("CRITICAL",0) or 0),
        "high": int(sev.get("HIGH",0) or 0),
        "medium": int(sev.get("MEDIUM",0) or 0),
        "low": int(sev.get("LOW",0) or 0),
        "info": int(sev.get("INFO",0) or 0),
    }
    return jsonify(ok=True, rid=rid, items=[], total=0, sev=sev, kpis=kpis, total_findings=int(total), from_path=fpath)

try:
    @app.before_request
    def vsp_before_request_v3_disk_override_v2():
        try:
            r = _vsp_override_v3_if_match()
            return r
        except Exception:
            return None
except Exception:
    pass

# ===== /VSP_V3_FROM_DISK_OVERRIDE_V2 =====
"""
    s = s + patch

p.write_text(s, encoding="utf-8")
print("[OK] disabled_blocks=", changed)
PY

python3 -m py_compile "$APP"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.7
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

for ep in findings_page_v3 dashboard_v3 run_gate_v3; do
  echo "== $ep =="
  curl -fsS "$BASE/api/vsp/$ep?rid=$RID&limit=10&offset=0" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"items_len=",(len(j.get("items") or []) if isinstance(j.get("items"),list) else None),"total_findings=",j.get("total_findings"),"sev=",j.get("sev"),"from_path=",j.get("from_path"))'
done

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"
