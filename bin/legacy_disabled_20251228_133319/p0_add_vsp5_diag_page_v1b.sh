#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PY="vsp_demo_app.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$PY" ] || { echo "[ERR] missing $PY"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$PY" "${PY}.bak_diag_v1b_${TS}"
echo "[BACKUP] ${PY}.bak_diag_v1b_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_VSP5_DIAG_PAGE_V1B"

if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block=textwrap.dedent(r"""
    # ===================== VSP_P0_VSP5_DIAG_PAGE_V1B =====================
    try:
        import os, glob, json, time
        import html as _html
        from flask import Response

        _VSP_DIAG_ROOTS_V1B = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
        ]

        def _vsp_diag_find_run_dir_v1b(rid: str):
            if not rid: return None
            for root in _VSP_DIAG_ROOTS_V1B:
                d = os.path.join(root, rid)
                if os.path.isdir(d):
                    return d
            return None

        def _vsp_diag_pick_semgrep_v1b(run_dir: str):
            cand = os.path.join(run_dir, "semgrep", "semgrep.json")
            if os.path.isfile(cand) and os.path.getsize(cand) > 200:
                return cand
            hits=[]
            for f in glob.glob(os.path.join(run_dir, "**", "*semgrep*.json"), recursive=True):
                try:
                    if os.path.getsize(f) > 200:
                        hits.append((os.path.getsize(f), f))
                except Exception:
                    pass
            hits.sort(reverse=True)
            return hits[0][1] if hits else None

        def _vsp_diag_norm_sev_v1b(sev: str):
            if not sev: return "INFO"
            x = str(sev).strip().upper()
            if x in ("ERROR","ERR"): return "HIGH"
            if x in ("WARNING","WARN"): return "MEDIUM"
            if x in ("INFO","INFORMATION"): return "INFO"
            if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"): return x
            return "INFO"

        def _vsp_diag_parse_semgrep_v1b(path: str, limit: int = 10):
            items=[]
            try:
                j=json.load(open(path,"r",encoding="utf-8",errors="ignore"))
            except Exception:
                return items
            results = j.get("results") if isinstance(j, dict) else None
            if not isinstance(results, list):
                return items
            for r in results:
                if not isinstance(r, dict): 
                    continue
                extra = r.get("extra") or {}
                sev = _vsp_diag_norm_sev_v1b(extra.get("severity") or extra.get("level") or "")
                msg = extra.get("message") or ""
                check_id = r.get("check_id") or r.get("rule_id") or ""
                title = (msg or check_id or "Semgrep finding").strip()
                fpath = (r.get("path") or "").strip()
                start = r.get("start") or {}
                line = start.get("line") if isinstance(start, dict) else ""
                items.append({
                    "severity": sev,
                    "tool": "semgrep",
                    "title": title,
                    "file": fpath,
                    "line": str(line) if line is not None else "",
                })
                if len(items) >= limit:
                    break
            return items

        @app.get("/vsp5_diag")
        def vsp5_diag_page_v1b():
            # best-effort rid from existing endpoint (already stable)
            rid = ""
            try:
                ridj = api_vsp_rid_latest_gate_root().get_json()  # type: ignore
                rid = (ridj or {}).get("rid","") or ""
            except Exception:
                rid = ""

            ok = False
            source = ""
            err = ""
            items = []

            run_dir = _vsp_diag_find_run_dir_v1b(rid) if rid else None
            if not run_dir:
                err = "run_dir not found"
            else:
                sf = _vsp_diag_pick_semgrep_v1b(run_dir)
                if not sf:
                    err = "semgrep.json not found"
                else:
                    items = _vsp_diag_parse_semgrep_v1b(sf, 10)
                    if items:
                        ok = True
                        source = "semgrep:" + os.path.relpath(sf, run_dir).replace("\\","/")
                    else:
                        err = "semgrep parsed but no results"
                        source = "semgrep:" + os.path.relpath(sf, run_dir).replace("\\","/")

            rows=[]
            for it in items[:10]:
                rows.append(
                    "<tr>"
                    f"<td>{_html.escape(str(it.get('severity','')))}</td>"
                    f"<td>{_html.escape(str(it.get('tool','')))}</td>"
                    f"<td>{_html.escape(str(it.get('title','')))}</td>"
                    f"<td>{_html.escape(str(it.get('file','')))}:{_html.escape(str(it.get('line','')))}</td>"
                    "</tr>"
                )

            # NO f-string to avoid CSS braces issues
            body = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VSP - vsp5_diag</title>
<style>
  body{font-family:system-ui,Segoe UI,Arial;margin:18px;background:#0a0e1a;color:#e6e9f2}
  .card{border:1px solid rgba(255,255,255,.12);border-radius:12px;padding:12px;background:rgba(255,255,255,.03)}
  table{width:100%;border-collapse:collapse;margin-top:10px;font-size:13px}
  th,td{padding:8px;border-top:1px solid rgba(255,255,255,.08);text-align:left}
  th{opacity:.75}
  .muted{opacity:.75}
  code{background:rgba(255,255,255,.06);padding:2px 6px;border-radius:8px}
</style>
</head><body>
  <div class="card">
    <div><b>vsp5_diag</b> <span class="muted">(server-render, no JS bundle)</span></div>
    <div class="muted">rid_latest_gate_root: <code>__RID__</code></div>
    <div class="muted">ok: <code>__OK__</code> source: <code>__SRC__</code></div>
    <div class="muted">err: <code>__ERR__</code></div>
    <table>
      <thead><tr><th>Sev</th><th>Tool</th><th>Title</th><th>Loc</th></tr></thead>
      <tbody>__ROWS__</tbody>
    </table>
  </div>
</body></html>"""
            body = body.replace("__RID__", _html.escape(rid or ""))
            body = body.replace("__OK__", _html.escape(str(ok)))
            body = body.replace("__SRC__", _html.escape(source or ""))
            body = body.replace("__ERR__", _html.escape(err or ""))
            body = body.replace("__ROWS__", "".join(rows) if rows else '<tr><td colspan="4" class="muted">No rows</td></tr>')
            return Response(body, mimetype="text/html; charset=utf-8")
        print("[VSP_P0_VSP5_DIAG_PAGE_V1B] enabled")
    except Exception as _e:
        print("[VSP_P0_VSP5_DIAG_PAGE_V1B] ERROR:", _e)
    # ===================== /VSP_P0_VSP5_DIAG_PAGE_V1B =====================
    """).strip("\n") + "\n"

    p.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile ok")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== quick check /vsp5_diag =="
curl -sS -o /dev/null -w "code=%{http_code} bytes=%{size_download}\n" "$BASE/vsp5_diag"
echo "[DONE] Open: $BASE/vsp5_diag"
