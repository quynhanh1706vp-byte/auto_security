#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_relcenter_${TS}"
echo "[BACKUP] ${WSGI}.bak_relcenter_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P2_RELEASE_CENTER_MW_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

block = r'''
# ===================== VSP_P2_RELEASE_CENTER_MW_V1 =====================
def _vsp__release_list_v1(limit=50):
    try:
        import json
        from pathlib import Path
        rel = Path("/home/test/Data/SECURITY_BUNDLE/ui/releases")
        if not rel.exists():
            return []
        mans = sorted(rel.glob("VSP_RELEASE_*_*.manifest.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        out=[]
        for mp in mans[: max(1, min(int(limit), 500))]:
            try:
                j = json.loads(mp.read_text(encoding="utf-8", errors="replace"))
            except Exception:
                j = {"ok": False}
            j["manifest_path"] = str(mp)
            try:
                st = mp.stat()
                j["manifest_mtime"] = int(st.st_mtime)
                j["manifest_size"] = int(st.st_size)
            except Exception:
                pass
            out.append(j)
        return out
    except Exception:
        return []

def _vsp__wsgi_release_center_mw_v1(_app):
    import json, time, os
    from urllib.parse import parse_qs

    def _resp_json(start_response, obj, status="200 OK"):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        start_response(status, [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(body))),
        ])
        return [body]

    def _resp_html(start_response, html, status="200 OK"):
        body = html.encode("utf-8")
        start_response(status, [
            ("Content-Type","text/html; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(body))),
        ])
        return [body]

    def _mw(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = parse_qs(environ.get("QUERY_STRING") or "")

        if path == "/api/vsp/release_list":
            lim = (qs.get("limit",["50"])[0] or "50").strip()
            try: lim_i = int(lim)
            except Exception: lim_i = 50
            releases = _vsp__release_list_v1(lim_i)
            return _resp_json(start_response, {"ok": True, "count": len(releases), "releases": releases, "ts": int(time.time())})

        if path == "/releases":
            releases = _vsp__release_list_v1(200)
            rows=[]
            for j in releases:
                rid = (j.get("rid") or "")
                dl = (j.get("download_url") or ("/api/vsp/release_download?rid=%s" % rid))
                au = (j.get("audit_url") or ("/api/vsp/release_audit?rid=%s" % rid))
                sha = (j.get("package_sha256") or "")
                pkg = (j.get("package_path") or "")
                ts = j.get("created_ts") or j.get("manifest_mtime") or ""
                rows.append(f"""
<tr>
  <td style="padding:8px 10px;border-bottom:1px solid #222">{rid}</td>
  <td style="padding:8px 10px;border-bottom:1px solid #222">{ts}</td>
  <td style="padding:8px 10px;border-bottom:1px solid #222;max-width:520px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis" title="{pkg}">{pkg}</td>
  <td style="padding:8px 10px;border-bottom:1px solid #222;max-width:340px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis" title="{sha}">{sha}</td>
  <td style="padding:8px 10px;border-bottom:1px solid #222">
    <a href="{dl}">Download</a> |
    <a href="{au}">Audit</a> |
    <a href="/vsp5?rid={rid}">Open</a>
  </td>
</tr>
""")

            html = f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>VSP Releases</title>
<style>
  body{{background:#0b1020;color:#e6e8ef;font-family:ui-sans-serif,system-ui;padding:18px}}
  h1{{margin:0 0 8px 0}}
  .sub{{opacity:.8;margin-bottom:14px}}
  table{{width:100%;border-collapse:collapse;background:rgba(255,255,255,.03);border:1px solid #222;border-radius:10px;overflow:hidden}}
  a{{color:#8ab4f8;text-decoration:none}}
  a:hover{{text-decoration:underline}}
</style></head>
<body>
  <h1>Releases</h1>
  <div class="sub">List manifests in <code>/home/test/Data/SECURITY_BUNDLE/ui/releases</code></div>
  <table>
    <thead>
      <tr>
        <th style="text-align:left;padding:10px;border-bottom:1px solid #222">RID</th>
        <th style="text-align:left;padding:10px;border-bottom:1px solid #222">TS</th>
        <th style="text-align:left;padding:10px;border-bottom:1px solid #222">Package path</th>
        <th style="text-align:left;padding:10px;border-bottom:1px solid #222">SHA256</th>
        <th style="text-align:left;padding:10px;border-bottom:1px solid #222">Actions</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows) if rows else '<tr><td style="padding:12px" colspan="5">No releases found</td></tr>'}
    </tbody>
  </table>
</body></html>"""
            return _resp_html(start_response, html)

        return _app(environ, start_response)

    return _mw

try:
    application = _vsp__wsgi_release_center_mw_v1(application)
    print("[VSP_P2_RELEASE_CENTER_MW_V1] installed on application")
except Exception as _e:
    try:
        print("[VSP_P2_RELEASE_CENTER_MW_V1] install failed:", repr(_e))
    except Exception:
        pass
# =================== end VSP_P2_RELEASE_CENTER_MW_V1 ===================
'''.strip("\n") + "\n"

p.write_text(s + "\n\n" + block, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

systemctl restart "$SVC" || true
sleep 0.8
systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] $SVC active" || { echo "[ERR] service not active"; systemctl --no-pager status "$SVC" -n 80 || true; exit 2; }

echo "== verify =="
curl -fsS "$BASE/api/vsp/release_list?limit=3" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"count=",j.get("count")); print("first_rid=", (j.get("releases") or [{}])[0].get("rid"))'
echo "[OK] open: $BASE/releases"
