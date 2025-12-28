#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

BAK="${PYF}.bak_runfileallow_cap_${TS}"
cp -f "$PYF" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

start = "# ===================== VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1C3 ====================="
end   = "# ===================== /VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1C3 ====================="

new_block = textwrap.dedent(r"""
# ===================== VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1D =====================
# Commercial-safe run_file_allow:
# - ALWAYS 200 JSON on error (no upstream 5xx wrapping)
# - multi-root run dir resolution
# - special-case findings_unified.json: serve SMALL sample (limit) from reports/findings_unified.csv
# - fallback to reports/ for other files
import os, json, csv, time
from flask import request, jsonify, send_file, Response

_VSP_RF_CACHE_V1D = {}

def _vsp_rf_roots_v1d():
    # Prefer explicit env first
    env = os.environ.get("VSP_RUN_ROOTS") or os.environ.get("VSP_OUT_CI_ROOTS") or ""
    roots = []
    for x in [y.strip() for y in env.split(":") if y.strip()]:
        if os.path.isdir(x) and x not in roots:
            roots.append(x)

    # Known defaults (tuned for your setup)
    defaults = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY/out_ci",
    ]
    for d in defaults:
        if os.path.isdir(d) and d not in roots:
            roots.append(d)
    return roots

def _vsp_rf_find_run_dir_v1d(rid: str):
    if not rid or len(rid) > 128:
        return None
    # deny path tricks
    if "/" in rid or "\\" in rid or "\x00" in rid:
        return None
    for root in _vsp_rf_roots_v1d():
        cand = os.path.join(root, rid)
        if os.path.isdir(cand):
            return cand
    return None

def _vsp_rf_safe_relpath_v1d(path: str):
    if not path or len(path) > 512:
        return None
    if "\x00" in path:
        return None
    if path.startswith("/") or path.startswith("\\"):
        return None
    if ".." in path.split("/"):
        return None
    if "\\" in path:
        return None
    return path

def _vsp_rf_guess_mime_v1d(fp: str):
    f = fp.lower()
    if f.endswith(".json"): return "application/json; charset=utf-8"
    if f.endswith(".csv"):  return "text/csv; charset=utf-8"
    if f.endswith(".sarif"):return "application/json; charset=utf-8"
    if f.endswith(".txt") or f.endswith(".log"): return "text/plain; charset=utf-8"
    if f.endswith(".html"): return "text/html; charset=utf-8"
    return "application/octet-stream"

def _vsp_rf_csv_sample_v1d(csv_path: str, limit: int):
    items = []
    counts = {}
    # tolerate weird headers; keep best-effort columns
    with open(csv_path, "r", encoding="utf-8", errors="replace", newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if i >= limit:
                break

            def pick(*keys):
                for k in keys:
                    v = row.get(k)
                    if v is not None and str(v).strip() != "":
                        return str(v)
                return ""

            sev  = pick("severity","Severity","SEVERITY","sev","Sev").upper()
            tool = pick("tool","Tool","TOOL","scanner","Scanner").lower()
            title = pick("title","Title","TITLE","rule_name","Rule","name","Name")
            loc = pick("location","Location","LOCATION","path","Path","file","File")
            line = pick("line","Line","LINE")
            if line and loc and ":" not in loc:
                loc = f"{loc}:{line}"

            item = {
                "severity": sev or "INFO",
                "tool": tool or "unknown",
                "title": title or "(no title)",
                "location": loc or "",
            }

            # keep a few optional fields if present
            for k in ("rule_id","rule","cwe","owasp","iso27001","confidence","fingerprint","remediation","category"):
                v = pick(k, k.upper(), k.title())
                if v:
                    item[k] = v

            items.append(item)
            counts[item["severity"]] = counts.get(item["severity"], 0) + 1

    return items, counts

@app.get("/api/vsp/run_file_allow")
def vsp_run_file_allow_v1d():
    rid = (request.args.get("rid") or "").strip()
    path = (request.args.get("path") or "").strip()

    safe = _vsp_rf_safe_relpath_v1d(path)
    run_dir = _vsp_rf_find_run_dir_v1d(rid)

    if not run_dir:
        return jsonify(ok=False, err="unknown rid", rid=rid, path=path, marker="VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1D"), 200
    if not safe:
        return jsonify(ok=False, err="bad path", rid=rid, path=path, marker="VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1D"), 200

    # --- Special-case: findings_unified.json (avoid freezing dashboard) ---
    if safe == "findings_unified.json":
        max_bytes = 6 * 1024 * 1024  # 6MB cap for direct JSON
        limit = request.args.get("limit", "300").strip()
        try:
            limit_i = max(10, min(int(limit), 1000))
        except Exception:
            limit_i = 300

        direct_jsons = [
            os.path.join(run_dir, "findings_unified.json"),
            os.path.join(run_dir, "reports", "findings_unified.json"),
        ]
        for fp in direct_jsons:
            if os.path.isfile(fp):
                try:
                    if os.path.getsize(fp) <= max_bytes:
                        return send_file(fp, mimetype="application/json; charset=utf-8", conditional=False)
                except Exception:
                    pass

        csvp = os.path.join(run_dir, "reports", "findings_unified.csv")
        if os.path.isfile(csvp):
            try:
                mtime = os.path.getmtime(csvp)
            except Exception:
                mtime = 0.0
            ck = (run_dir, csvp, limit_i, mtime)
            cached = _VSP_RF_CACHE_V1D.get(ck)
            if cached and (time.time() - cached["ts"] < 60):
                return Response(cached["body"], mimetype="application/json; charset=utf-8")

            try:
                items, counts = _vsp_rf_csv_sample_v1d(csvp, limit_i)
                body = json.dumps({
                    "meta": {
                        "rid": rid,
                        "generated_from": csvp,
                        "generated_ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "truncated": True,
                        "limit": limit_i,
                        "counts_by_severity_sample": counts,
                    },
                    "findings": items
                }, ensure_ascii=False)
                _VSP_RF_CACHE_V1D[ck] = {"ts": time.time(), "body": body}
                return Response(body, mimetype="application/json; charset=utf-8")
            except Exception as e:
                return jsonify(ok=False, err=f"csv parse failed: {e}", rid=rid, path=path, run_dir=run_dir,
                               marker="VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1D"), 200

        return jsonify(ok=False, err="missing file", rid=rid, path=path, run_dir=run_dir,
                       marker="VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1D"), 200

    # --- Generic: serve file in run_dir ---
    full = os.path.join(run_dir, safe)
    if os.path.isfile(full):
        try:
            # guard huge text/json to protect UI
            if full.lower().endswith((".json",".csv",".sarif",".log",".txt")) and os.path.getsize(full) > 20*1024*1024:
                return jsonify(ok=False, err="file too large", rid=rid, path=path, size=os.path.getsize(full), run_dir=run_dir,
                               marker="VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1D"), 200
        except Exception:
            pass
        return send_file(full, mimetype=_vsp_rf_guess_mime_v1d(full), conditional=False)

    # Fallback: reports/<path>
    if not safe.startswith("reports/"):
        alt = os.path.join(run_dir, "reports", safe)
        if os.path.isfile(alt):
            return send_file(alt, mimetype=_vsp_rf_guess_mime_v1d(alt), conditional=False)

    return jsonify(ok=False, err="missing file", rid=rid, path=path, run_dir=run_dir,
                   marker="VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1D"), 200

# ===================== /VSP_P0_RUN_FILE_ALLOW_MULTIROOT_ALWAYS200_V1D =====================
""").strip() + "\n"

if start in s and end in s:
    pre = s.split(start, 1)[0]
    post = s.split(end, 1)[1]
    # Replace old block entirely
    s2 = pre + new_block + post
    p.write_text(s2, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] replaced V1C3 block -> V1D")
else:
    # If markers not found, do NOT risk duplicate route
    raise SystemExit("[ERR] cannot find V1C3 marker block to replace (refuse to append to avoid duplicate route)")

PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] patched run_file_allow (V1D) + restarted $SVC"
