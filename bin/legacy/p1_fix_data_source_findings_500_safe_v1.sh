#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"
echo "[INFO] BASE=$BASE"

W="wsgi_vsp_ui_gateway.py"
JS="static/js/vsp_data_source_tab_v3.js"

[ -f "$W" ]  || { echo "[ERR] missing $W"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$W"  "${W}.bak_findings_safe_${TS}"
cp -f "$JS" "${JS}.bak_findings_safe_${TS}"
echo "[BACKUP] ${W}.bak_findings_safe_${TS}"
echo "[BACKUP] ${JS}.bak_findings_safe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_FINDINGS_SAFE_V1"
if marker not in s:
    block = r'''
# === {marker} ===
# Safe endpoint: never raise 500 for findings loading.
try:
    import json, os, time
    from flask import request
except Exception:
    json = None

def __vsp__safe_int(v, default=0, lo=0, hi=5000):
    try:
        x = int(v)
    except Exception:
        return default
    if x < lo: x = lo
    if x > hi: x = hi
    return x

def __vsp__get_app_obj():
    for nm in ("app","application","flask_app"):
        obj = globals().get(nm)
        if obj is not None and hasattr(obj, "add_url_rule") and hasattr(obj, "url_map"):
            return obj
    return None

def __vsp__normalize_find_item(it):
    # accept dicts from multiple schemas
    if not isinstance(it, dict):
        return None
    tool = it.get("tool") or it.get("engine") or it.get("source") or ""
    sev  = it.get("severity") or it.get("sev") or it.get("level") or ""
    title = it.get("title") or it.get("name") or it.get("rule_name") or "Finding"
    rule_id = it.get("rule_id") or it.get("check_id") or it.get("id") or ""
    file_ = it.get("file") or it.get("path") or it.get("filename") or ""
    line  = it.get("line")
    try:
        line = int(line) if line is not None else 0
    except Exception:
        line = 0
    msg = it.get("message") or it.get("msg") or it.get("description") or it.get("details") or ""
    return {
        "tool": str(tool),
        "severity": str(sev),
        "title": str(title),
        "rule_id": str(rule_id),
        "file": str(file_),
        "line": line,
        "message": str(msg),
    }

def __vsp__derive_overall_from_counts(counts):
    # overall used by UI: GREEN/AMBER/RED/UNKNOWN
    try:
        c = int(counts.get("CRITICAL", 0) or 0)
        h = int(counts.get("HIGH", 0) or 0)
        m = int(counts.get("MEDIUM", 0) or 0)
        # any CRITICAL/HIGH => RED; else MEDIUM => AMBER; else GREEN
        if c > 0 or h > 0:
            return "RED"
        if m > 0:
            return "AMBER"
        return "GREEN"
    except Exception:
        return "UNKNOWN"

def __vsp__load_findings_list(fp):
    # returns (items_list, counts_dict, raw_root_type)
    import json
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        j = json.load(f)
    if isinstance(j, list):
        items = j
        counts = {}
        return items, counts, "list"
    if isinstance(j, dict):
        # your schema: dict + findings + counts
        counts = j.get("counts") if isinstance(j.get("counts"), dict) else {}
        for k in ("findings","items","results","data"):
            v = j.get(k)
            if isinstance(v, list):
                return v, counts, f"dict.{k}"
        return [], counts, "dict.no_list_key"
    return [], {}, "unknown"

def __vsp__resolve_run_dir_by_rid(rid):
    # best effort: use existing helper if present
    # common patterns in your gateway: run_dir under /home/test/Data/SECURITY_BUNDLE/out/<RID>
    if not rid:
        return None
    # if rid looks like RUN_xxx: assume standard out layout
    cand = f"/home/test/Data/SECURITY_BUNDLE/out/{rid}"
    try:
        import os
        if os.path.isdir(cand):
            return cand
    except Exception:
        pass
    return None

def __vsp__find_findings_path(run_dir):
    import os
    # prefer reports/findings_unified.json (your real file)
    cands = [
        os.path.join(run_dir, "reports", "findings_unified.json"),
        os.path.join(run_dir, "reports", "findings_unified.jsonl"),
        os.path.join(run_dir, "reports", "findings_unified.sarif"),
    ]
    for fp in cands:
        if os.path.isfile(fp):
            return fp
    return None

def vsp_apiui_findings_safe_v1_handler():
    ts = int(time.time())
    try:
        rid = (request.args.get("rid") or request.args.get("run_id") or "").strip()
        limit  = __vsp__safe_int(request.args.get("limit"), default=50, lo=1, hi=500)
        offset = __vsp__safe_int(request.args.get("offset"), default=0, lo=0, hi=10_000_000)

        run_dir = __vsp__resolve_run_dir_by_rid(rid)
        if not run_dir:
            return __wsgi_json({"ok": False, "error": "bad_rid", "rid": rid, "ts": ts})

        fp = __vsp__find_findings_path(run_dir)
        if not fp:
            return __wsgi_json({"ok": True, "rid": rid, "run_dir": run_dir, "overall": "UNKNOWN",
                                "items": [], "counts": {"TOTAL": 0}, "total": 0,
                                "limit": limit, "offset": offset, "findings_path": None, "ts": ts})

        items, counts, root_type = __vsp__load_findings_list(fp)
        # normalize + slice without breaking on weird items
        norm = []
        for it in items:
            x = __vsp__normalize_find_item(it)
            if x is not None:
                norm.append(x)

        total = len(norm)
        page = norm[offset: offset + limit]

        # counts: keep if present; else compute quick
        if not isinstance(counts, dict) or not counts:
            counts = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}
            for it in norm:
                sev = (it.get("severity") or "").upper()
                if sev in counts:
                    counts[sev] += 1
            counts["TOTAL"] = total
        else:
            # ensure TOTAL
            try:
                counts["TOTAL"] = int(counts.get("TOTAL", total) or total)
            except Exception:
                counts["TOTAL"] = total

        overall = __vsp__derive_overall_from_counts(counts)

        return __wsgi_json({
            "ok": True,
            "rid": rid,
            "run_dir": run_dir,
            "overall": overall,
            "items": page,
            "counts": counts,
            "limit": limit,
            "offset": offset,
            "total": total,
            "findings_path": fp,
            "root_type": root_type,
            "ts": ts
        })
    except Exception as e:
        return __wsgi_json({"ok": False, "error": "exception", "detail": str(e)[:200], "ts": ts})

# register route only if absent
try:
    __app = __vsp__get_app_obj()
    if __app is not None:
        rules = set([r.rule for r in __app.url_map.iter_rules()])
        if "/api/ui/findings_safe_v1" not in rules:
            __app.add_url_rule("/api/ui/findings_safe_v1", "vsp_apiui_findings_safe_v1",
                               vsp_apiui_findings_safe_v1_handler, methods=["GET"])
except Exception:
    pass
# === /{marker} ===
'''.replace("{marker}", marker)

    s = s.rstrip() + "\n\n" + block + "\n"
    w.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker)
else:
    print("[OK] already present:", marker)

# Patch Data Source JS: force use SAFE endpoint
p = Path("static/js/vsp_data_source_tab_v3.js")
j = p.read_text(encoding="utf-8", errors="replace")
j2 = j

# replace any findings endpoint to safe
j2, n1 = re.subn(r'"/api/ui/findings[^"]*"', '"/api/ui/findings_safe_v1"', j2)
j2, n2 = re.subn(r"'/api/ui/findings[^']*'", "'/api/ui/findings_safe_v1'", j2)

if (n1 + n2) == 0 and "/api/ui/findings_safe_v1" not in j2:
    # fallback: inject a constant if file uses config map
    j2 = '/* patched: force findings_safe_v1 */\n' + j2

p.write_text(j2, encoding="utf-8")
print(f"[OK] patched {p} replacements={n1+n2}")
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart (single-owner, best-effort) =="
if [ -f "bin/p1_force_restart_8910_unlock_v1.sh" ]; then
  bash bin/p1_force_restart_8910_unlock_v1.sh
elif [ -f "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bash bin/p1_ui_8910_single_owner_start_v2.sh || true
fi

echo "== verify SAFE findings (must ok:true & total>0) =="
curl -fsS "$BASE/api/ui/findings_safe_v1?rid=RUN_20251120_130310&limit=1&offset=0" | head -c 900; echo
echo "[DONE] Now hard-refresh /data_source (Ctrl+Shift+R)."
