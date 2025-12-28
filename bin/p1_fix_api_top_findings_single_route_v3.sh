#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_single_v3_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_single_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_API_TOP_FINDINGS_SINGLE_ROUTE_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Rename ALL existing rules for /api/vsp/top_findings_v1 -> ...__oldN
pat_get   = re.compile(r'(@app\.get\(\s*["\']/api/vsp/top_findings_v1["\']\s*\))')
pat_route = re.compile(r'(@app\.route\(\s*["\']/api/vsp/top_findings_v1["\']\s*,[^)]*\))')

i = 0
def _ren(m):
    global i
    i += 1
    line = m.group(1)
    # replace only the path string, keep decorator shape
    line2 = re.sub(r'(["\'])/api/vsp/top_findings_v1\1', r'\1/api/vsp/top_findings_v1__old%02d\1' % i, line)
    return line2 + f"  # {MARK}_DISABLED_{i:02d}"

s2, n1 = pat_get.subn(_ren, s)
s3, n2 = pat_route.subn(_ren, s2)

print(f"[OK] renamed existing routes: app.get={n1}, app.route={n2}")

# 2) Append ONE canonical handler (honor rid strictly)
block = r'''
# ===================== {MARK} =====================
# Single canonical handler for /api/vsp/top_findings_v1 (honor rid strictly).
try:
    from flask import request, jsonify
except Exception:
    request = None
    jsonify = None

def _vsp__sanitize_str(x, maxlen=220):
    try:
        x = "" if x is None else str(x)
        x = x.replace("\r"," ").replace("\n"," ").strip()
        return x[:maxlen]
    except Exception:
        return ""

def _vsp__severity_rank(sev: str) -> int:
    sev = (sev or "").upper().strip()
    order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
    try:
        return order.index(sev)
    except Exception:
        return 99

def _vsp__find_rid_dir(rid: str):
    rid = (rid or "").strip()
    if not rid:
        return None

    # common roots in your project
    roots = [
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        Path("/home/test/Data/SECURITY-10-10-v4/out_ci"),
    ]
    for root in roots:
        try:
            cand = root / rid
            if cand.exists() and cand.is_dir():
                return cand
        except Exception:
            pass
    return None

def _vsp__pick_rid_latest():
    roots = [
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        Path("/home/test/Data/SECURITY-10-10-v4/out_ci"),
    ]
    best = None
    best_mtime = -1.0
    for root in roots:
        try:
            if not root.exists():
                continue
            for d in root.iterdir():
                if not d.is_dir():
                    continue
                name = d.name
                if not (name.startswith("VSP_") or name.startswith("RUN_")):
                    continue
                try:
                    mt = d.stat().st_mtime
                    if mt > best_mtime:
                        best_mtime = mt
                        best = name
                except Exception:
                    continue
        except Exception:
            continue
    return best or ""

def _vsp__load_findings_list(rid_dir: Path):
    import json
    candidates = [
        rid_dir / "findings_unified.json",
        rid_dir / "reports" / "findings_unified.json",
        rid_dir / "report" / "findings_unified.json",
    ]
    for fp in candidates:
        try:
            if not fp.exists():
                continue
            raw = fp.read_text(encoding="utf-8", errors="replace").strip()
            if not raw:
                continue
            obj = json.loads(raw)
            # normalize
            if isinstance(obj, list):
                return obj, fp.name
            if isinstance(obj, dict):
                for k in ("findings","items","results","data"):
                    v = obj.get(k)
                    if isinstance(v, list):
                        return v, fp.name
                # dict but not list-like
                return [], fp.name
        except Exception:
            continue
    return [], ""

def _vsp__normalize_item(it: dict):
    if not isinstance(it, dict):
        return None
    tool = _vsp__sanitize_str(it.get("tool") or it.get("scanner") or it.get("engine") or "")
    sev  = _vsp__sanitize_str(it.get("severity") or it.get("level") or it.get("priority") or "")
    title = _vsp__sanitize_str(it.get("title") or it.get("message") or it.get("name") or "")
    cwe = it.get("cwe")
    cwe = None if cwe in ("", "null", "None") else cwe
    rule_id = _vsp__sanitize_str(it.get("rule_id") or it.get("check_id") or it.get("id") or "")

    # avoid leaking internal paths
    filev = it.get("file") or it.get("path") or it.get("location") or ""
    filev = _vsp__sanitize_str(filev, 120)
    # if looks like absolute path, keep only basename-ish tail
    if "/" in filev:
        filev = filev.split("/")[-1]

    line = it.get("line")
    try:
        line = int(line) if line is not None else None
    except Exception:
        line = None

    component = _vsp__sanitize_str(it.get("component") or it.get("package") or it.get("artifact") or "")
    version   = _vsp__sanitize_str(it.get("version") or it.get("installed_version") or "")

    return {
        "tool": tool,
        "severity": (sev or "").upper(),
        "title": title,
        "component": component,
        "version": version,
        "cwe": cwe if isinstance(cwe,(int,str)) else None,
        "rule_id": rule_id,
        "file": filev,
        "line": line,
    }

@app.get("/api/vsp/top_findings_v1")
def vsp_top_findings_v1_single_v3():
    # NOTE: rid passed => MUST be honored (never auto-switch).
    rid_req = ""
    limit = 25
    try:
        rid_req = (request.args.get("rid") or "").strip()
    except Exception:
        rid_req = ""

    try:
        limit = int(request.args.get("limit") or 25)
    except Exception:
        limit = 25
    if limit < 1: limit = 1
    if limit > 200: limit = 200

    bad_tokens = {"YOUR_RID","__YOUR_RID__","NONE","NULL","UNDEFINED"}
    if rid_req and rid_req.upper() in bad_tokens:
        rid_req = ""

    rid_used = rid_req or _vsp__pick_rid_latest()
    rid_dir = _vsp__find_rid_dir(rid_used) if rid_used else None

    items = []
    src = ""
    if rid_dir:
        raw_list, src = _vsp__load_findings_list(rid_dir)
        norm = []
        for it in (raw_list or []):
            ni = _vsp__normalize_item(it)
            if ni:
                norm.append(ni)
        # sort: severity then tool then title
        norm.sort(key=lambda x: (_vsp__severity_rank(x.get("severity")), x.get("tool",""), x.get("title","")))
        items = norm

    out = {
        "ok": True,
        "rid": rid_used,
        "rid_requested": rid_req or None,
        "rid_used": rid_used,
        "total": len(items),
        "limit_applied": limit,
        "items_truncated": len(items) > limit,
        "items": items[:limit],
        "reason": None if items else ("no findings for rid" if rid_used else "no rid"),
        "from": src or None,
    }
    return jsonify(out)
# =================== END {MARK} ===================
'''.replace("{MARK}", MARK)

s3 = s3 + "\n" + block
p.write_text(s3, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile PASS"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted: $SVC"
else
  echo "[WARN] systemctl not found; restart service manually"
fi

echo
echo "== [TEST] rid must be honored =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_TEST="${1:-VSP_CI_20251218_114312}"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=3&rid=$RID_TEST" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"rid_requested=",j.get("rid_requested"),"rid_used=",j.get("rid_used"),"items_len=",len(j.get("items") or []),"from=",j.get("from"))'
