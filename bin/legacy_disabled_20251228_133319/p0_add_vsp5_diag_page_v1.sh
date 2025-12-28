#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PY="vsp_demo_app.py"
[ -f "$PY" ] || { echo "[ERR] missing $PY"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$PY" "${PY}.bak_diag_${TS}"
echo "[BACKUP] ${PY}.bak_diag_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_VSP5_DIAG_PAGE_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block=textwrap.dedent(r"""
    # ===================== VSP_P0_VSP5_DIAG_PAGE_V1 =====================
    try:
        import html as _html
        from flask import Response

        @app.get("/vsp5_diag")
        def vsp5_diag_page_v1():
            # use existing APIs locally (no JS)
            try:
                ridj = api_vsp_rid_latest_gate_root().get_json()  # type: ignore
                rid = (ridj or {}).get("rid","")
            except Exception:
                rid = ""
            try:
                topj = api_vsp_top_findings_v4().get_json()  # type: ignore
            except Exception:
                topj = {"ok": False, "items": [], "err": "call top_findings_v4 failed"}
            items = (topj or {}).get("items") or []
            rows = []
            for it in items[:10]:
                rows.append(f"<tr><td>{_html.escape(str(it.get('severity','')))}</td>"
                            f"<td>{_html.escape(str(it.get('tool','')))}</td>"
                            f"<td>{_html.escape(str(it.get('title','')))}</td>"
                            f"<td>{_html.escape(str(it.get('file','')))}:{_html.escape(str(it.get('line','')))}</td></tr>")
            body = f"""
            <!doctype html><html><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>VSP • vsp5_diag</title>
            <style>
              body{{font-family:system-ui,Segoe UI,Arial;margin:18px;background:#0a0e1a;color:#e6e9f2}}
              .card{{border:1px solid rgba(255,255,255,.12);border-radius:12px;padding:12px;background:rgba(255,255,255,.03)}}
              table{{width:100%;border-collapse:collapse;margin-top:10px;font-size:13px}}
              th,td{{padding:8px;border-top:1px solid rgba(255,255,255,.08);text-align:left}}
              th{{opacity:.75}}
              .muted{{opacity:.75}}
              code{{background:rgba(255,255,255,.06);padding:2px 6px;border-radius:8px}}
            </style>
            </head><body>
              <div class="card">
                <div><b>vsp5_diag</b> <span class="muted">(no JS bundle)</span></div>
                <div class="muted">rid_latest_gate_root: <code>{_html.escape(rid)}</code></div>
                <div class="muted">top_findings_v4 ok: <code>{_html.escape(str((topj or {}).get('ok')))}</code> source: <code>{_html.escape(str((topj or {}).get('source','')))}</code></div>
                <table>
                  <thead><tr><th>Sev</th><th>Tool</th><th>Title</th><th>Loc</th></tr></thead>
                  <tbody>{''.join(rows) if rows else '<tr><td colspan=4 class="muted">No rows</td></tr>'}</tbody>
                </table>
              </div>
            </body></html>
            """
            return Response(body, mimetype="text/html; charset=utf-8")
        print("[VSP_P0_VSP5_DIAG_PAGE_V1] enabled")
    except Exception as _e:
        print("[VSP_P0_VSP5_DIAG_PAGE_V1] ERROR:", _e)
    # ===================== /VSP_P0_VSP5_DIAG_PAGE_V1 =====================
    """).strip("\n") + "\n"
    p.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile ok")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Open: http://127.0.0.1:8910/vsp5_diag"
