#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"
echo "[INFO] BASE=$BASE"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runsv3_${TS}"
echo "[BACKUP] ${W}.bak_runsv3_${TS}"

# backup JS candidates (best-effort)
for f in \
  static/js/vsp_tabs3_common_v3.js \
  static/js/vsp_data_source_tab_v3.js \
  static/js/vsp_settings_tab_v3.js \
  static/js/vsp_rule_overrides_tab_v3.js \
  static/js/vsp_runs_quick_actions_v1.js \
  static/js/vsp_runs_tab_v1.js \
  static/js/vsp_runs_v1.js \
  static/js/vsp_bundle_commercial_v2.js
do
  [ -f "$f" ] && cp -f "$f" "${f}.bak_runsv3_${TS}" || true
done

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_RUNS_V3_REALDATA_P1_V1"
if marker in s:
    print("[OK] marker already present, skip append:", marker)
else:
    block = r'''
# ===================== {MARKER} =====================
# 목적:
# - /api/ui/runs_v3: scan out/ runs, compute findings_total + overall, sort "real data" first
# - /api/ui/runs_kpi_v2 + /api/ui/runs_page_v2: KPI + pagination based on runs_v3 scan
try:
    import os as __os
    import json as __json
    import time as __time
    from flask import request as __request
    from flask import Response as __Response
except Exception as __e:
    __os = None; __json = None; __time = None; __request = None; __Response = None

def __vsp__json(payload, status=200):
    # prefer existing helper if present
    try:
        return __wsgi_json(payload, status)
    except Exception:
        if __Response is None:
            return payload
        return __Response(__json.dumps(payload, ensure_ascii=False), status=status, mimetype="application/json")

def __vsp__read_json(fp):
    try:
        with open(fp, "r", encoding="utf-8") as f:
            return __json.load(f)
    except Exception:
        return None

def __vsp__pick_overall(run_dir):
    # try run_gate.json, then run_gate_summary.json (fallback)
    cand = [
        __os.path.join(run_dir, "run_gate.json"),
        __os.path.join(run_dir, "run_gate_summary.json"),
        __os.path.join(run_dir, "SUMMARY.json"),
    ]
    for fp in cand:
        if __os.path.isfile(fp):
            j = __vsp__read_json(fp)
            if isinstance(j, dict):
                for k in ("overall_status", "overall", "status", "verdict", "final"):
                    v = j.get(k)
                    if isinstance(v, str) and v.strip():
                        return v.strip().upper()
                # sometimes nested
                v = j.get("overall", None)
                if isinstance(v, dict):
                    vv = v.get("status") or v.get("overall_status")
                    if isinstance(vv, str) and vv.strip():
                        return vv.strip().upper()
    return "UNKNOWN"

def __vsp__findings_meta(run_dir):
    fp = __os.path.join(run_dir, "reports", "findings_unified.json")
    if not __os.path.isfile(fp):
        return False, 0, None, None
    j = __vsp__read_json(fp)
    total = 0
    counts = None
    if isinstance(j, dict):
        counts = j.get("counts")
        if isinstance(counts, dict):
            # prefer TOTAL
            t = counts.get("TOTAL")
            if isinstance(t, int):
                total = t
            else:
                # some schemas use total/total_findings
                for k in ("total", "total_findings"):
                    v = counts.get(k)
                    if isinstance(v, int):
                        total = v
                        break
        # also support len(findings)
        if total == 0:
            v = j.get("findings")
            if isinstance(v, list):
                total = len(v)
    elif isinstance(j, list):
        total = len(j)
    return True, int(total or 0), fp, counts

def __vsp__scan_runs(root, cap=5000):
    items = []
    if __os is None:
        return items
    try:
        names = __os.listdir(root)
    except Exception:
        return items
    # only RUN_* folders
    runs = []
    for nm in names:
        if not nm.startswith("RUN_"):
            continue
        rd = __os.path.join(root, nm)
        if __os.path.isdir(rd):
            try:
                mt = int(__os.path.getmtime(rd))
            except Exception:
                mt = 0
            runs.append((mt, nm, rd))
    # newest first (base), then we'll resort with weights
    runs.sort(key=lambda x: x[0], reverse=True)

    for i, (mt, rid, rd) in enumerate(runs):
        if i >= cap:
            break
        has_f, total, fpath, counts = __vsp__findings_meta(rd)
        overall = __vsp__pick_overall(rd)
        items.append({
            "rid": rid,
            "run_dir": rd,
            "mtime": mt,
            "overall": overall,
            "has_findings": bool(has_f),
            "findings_total": int(total),
            "findings_path": fpath,
            "counts": counts if isinstance(counts, dict) else None,
            "has_gate": __os.path.isfile(__os.path.join(rd, "run_gate.json")) or __os.path.isfile(__os.path.join(rd, "run_gate_summary.json")),
        })
    return items

def __vsp__overall_weight(x):
    # higher = worse first (RED > AMBER > GREEN > UNKNOWN)
    o = (x or "").upper()
    if "RED" in o: return 3
    if "AMBER" in o or "YELLOW" in o: return 2
    if "GREEN" in o: return 1
    return 0

def __vsp__sort_realdata(items):
    # prioritize:
    # 1) findings_total desc (real data first)
    # 2) overall weight desc (RED/AMBER before GREEN/UNKNOWN)
    # 3) mtime desc
    items.sort(key=lambda it: (
        int(it.get("findings_total", 0)),
        __vsp__overall_weight(it.get("overall")),
        int(it.get("mtime", 0)),
    ), reverse=True)
    return items

try:
    app  # noqa
    __VSP_OUT_ROOT = "/home/test/Data/SECURITY_BUNDLE/out"

    @app.get("/api/ui/runs_v3")
    def vsp_apiui_runs_v3():
        limit = 200
        offset = 0
        try:
            if __request is not None:
                limit = int(__request.args.get("limit", limit))
                offset = int(__request.args.get("offset", offset))
        except Exception:
            pass
        limit = max(1, min(limit, 2000))
        offset = max(0, offset)

        items = __vsp__scan_runs(__VSP_OUT_ROOT, cap=8000)
        __vsp__sort_realdata(items)

        page = items[offset:offset+limit]
        return __vsp__json({
            "ok": True,
            "items": page,
            "limit": limit,
            "offset": offset,
            "total": len(items),
            "sorted": "findings_total_desc,overall_weight_desc,mtime_desc",
            "ts": int(__time.time()) if __time else 0
        })

    @app.get("/api/ui/runs_kpi_v2")
    def vsp_apiui_runs_kpi_v2():
        items = __vsp__scan_runs(__VSP_OUT_ROOT, cap=8000)
        __vsp__sort_realdata(items)
        by = {"GREEN": 0, "AMBER": 0, "RED": 0, "UNKNOWN": 0}
        total_findings = 0
        nonzero_runs = 0
        latest_rid = items[0]["rid"] if items else None
        for it in items:
            o = (it.get("overall") or "UNKNOWN").upper()
            if "RED" in o: by["RED"] += 1
            elif "AMBER" in o or "YELLOW" in o: by["AMBER"] += 1
            elif "GREEN" in o: by["GREEN"] += 1
            else: by["UNKNOWN"] += 1
            ft = int(it.get("findings_total", 0) or 0)
            total_findings += ft
            if ft > 0:
                nonzero_runs += 1
        return __vsp__json({
            "ok": True,
            "total_runs": len(items),
            "nonzero_runs": nonzero_runs,
            "total_findings": total_findings,
            "by_overall": by,
            "latest_rid": latest_rid,
            "ts": int(__time.time()) if __time else 0
        })

    @app.get("/api/ui/runs_page_v2")
    def vsp_apiui_runs_page_v2():
        # same as runs_v3, just explicit pagination endpoint for legacy UI code
        return vsp_apiui_runs_v3()

except Exception as __e:
    pass
# =================== END {MARKER} ===================
'''.replace("{MARKER}", marker)

    s = s.rstrip() + "\n" + block + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker)

PY

# Patch JS endpoints to use v3/v2 (safe, best-effort)
python3 - <<'PY'
from pathlib import Path
import re

targets = []
for pat in [
    "static/js/*.js",
]:
    targets += list(Path(".").glob(pat))

def patch_file(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    orig = s

    # prefer runs_v3
    s = s.replace("/api/ui/runs_v2", "/api/ui/runs_v3")
    s = s.replace("/api/ui/runs_v1", "/api/ui/runs_v3")  # some files used v1 naming

    # KPI/pagination prefer v2 (if referenced)
    s = s.replace("/api/ui/runs_kpi_v1", "/api/ui/runs_kpi_v2")
    s = s.replace("/api/ui/runs_page_v1", "/api/ui/runs_page_v2")

    # also patch hardcoded query strings
    s = s.replace("/api/ui/runs_v3?limit=160", "/api/ui/runs_v3?limit=200")

    if s != orig:
        fp.write_text(s, encoding="utf-8")
        return True
    return False

changed = []
for fp in targets:
    # skip backups
    if ".bak_" in fp.name:
        continue
    try:
        if patch_file(fp):
            changed.append(str(fp))
    except Exception:
        pass

print("[OK] patched JS files:", len(changed))
for x in changed[:40]:
    print(" -", x)
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || bin/p1_ui_8910_single_owner_start_v2.sh

echo "== verify endpoints =="
echo "--- runs_kpi_v2"
curl -fsS "$BASE/api/ui/runs_kpi_v2" | head -c 300; echo
echo "--- runs_v3 page(5)"
curl -fsS "$BASE/api/ui/runs_v3?limit=5&offset=0" | head -c 900; echo
echo "--- findings_v2 sanity (nonzero example)"
curl -fsS "$BASE/api/ui/findings_v2?rid=RUN_20251120_130310&limit=1&offset=0" | head -c 400; echo

echo "[DONE] Now open /runs, /data_source, /settings, /rule_overrides and hard-refresh (Ctrl+Shift+R)."
