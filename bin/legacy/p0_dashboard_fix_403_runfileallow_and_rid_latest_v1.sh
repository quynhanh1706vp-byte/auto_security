#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
WSGI="wsgi_vsp_ui_gateway.py"
BUNDLE="static/js/vsp_bundle_commercial_v2.js"

[ -f "$WSGI" ]   || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

cp -f "$WSGI"   "${WSGI}.bak_p0_dashfix_${TS}"
cp -f "$BUNDLE" "${BUNDLE}.bak_p0_dashfix_${TS}"
echo "[BACKUP] ${WSGI}.bak_p0_dashfix_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_p0_dashfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, time

wsgi = Path("wsgi_vsp_ui_gateway.py")
s = wsgi.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_API_RID_LATEST_GATE_ROOT_V1"
if marker not in s:
    addon = textwrap.dedent(r'''
    # ===================== VSP_P0_API_RID_LATEST_GATE_ROOT_V1 =====================
    # Back-compat endpoint for dashboard bundle: /api/vsp/rid_latest_gate_root
    try:
        from flask import jsonify
    except Exception:
        jsonify = None

    def _vsp_p0_scan_latest_gate_root_rid_v1():
        try:
            from pathlib import Path
            import re
            roots = [
                Path("/home/test/Data/SECURITY_BUNDLE/out"),
                Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
            ]
            pats = [
                re.compile(r"^VSP_CI_RUN_\d{8}_\d{6}$"),
                re.compile(r"^VSP_CI_\d{8}_\d{6}$"),
                re.compile(r"^RUN_\d{8}_\d{6}$"),
            ]
            cands = []
            for root in roots:
                if not root.exists() or not root.is_dir():
                    continue
                for p in root.iterdir():
                    if not p.is_dir():
                        continue
                    name = p.name
                    if any(rx.match(name) for rx in pats):
                        try:
                            cands.append((p.stat().st_mtime, name, str(root)))
                        except Exception:
                            pass
            cands.sort(reverse=True)
            if not cands:
                return None, {"roots": [str(r) for r in roots if r.exists()], "count": 0}
            mt, rid, root = cands[0]
            return rid, {"root": root, "mtime": mt, "count": len(cands)}
        except Exception as e:
            return None, {"err": str(e)}

    def _vsp_p0_register_rid_latest_gate_root_v1():
        g = globals()
        app_obj = g.get("application") or g.get("app")
        if not app_obj or jsonify is None:
            return False

        # Avoid double-register
        try:
            for rule in getattr(app_obj, "url_map").iter_rules():
                if str(getattr(rule, "rule", "")) == "/api/vsp/rid_latest_gate_root":
                    return True
        except Exception:
            pass

        @app_obj.get("/api/vsp/rid_latest_gate_root")
        def vsp_rid_latest_gate_root_v1():
            rid, meta = _vsp_p0_scan_latest_gate_root_rid_v1()
            return jsonify({"ok": bool(rid), "rid": rid or "", "meta": meta})

        return True

    try:
        _vsp_p0_register_rid_latest_gate_root_v1()
    except Exception:
        pass
    # ===================== /VSP_P0_API_RID_LATEST_GATE_ROOT_V1 =====================
    ''').strip("\n") + "\n"

    # Append at end (safe)
    wsgi.write_text(s + "\n\n" + addon, encoding="utf-8")
    print("[OK] appended WSGI endpoint:", marker)
else:
    print("[OK] WSGI already has:", marker)

bundle = Path("static/js/vsp_bundle_commercial_v2.js")
js = bundle.read_text(encoding="utf-8", errors="replace")

jmarker = "VSP_P0_RUNFILEALLOW_ENSURE_PATH_V1"
if jmarker not in js:
    fix = textwrap.dedent(r'''
    /* ===================== VSP_P0_RUNFILEALLOW_ENSURE_PATH_V1 =====================
       Fix 403 spam: some callers hit /api/vsp/run_file_allow without ?path=...
       We default path=run_gate_summary.json (safe “dashboard truth” file) for GET only.
    */
    (()=> {
      if (window.__vsp_p0_runfileallow_ensure_path_v1) return;
      window.__vsp_p0_runfileallow_ensure_path_v1 = true;

      const origFetch = window.fetch ? window.fetch.bind(window) : null;
      if (!origFetch) return;

      window.fetch = async function(input, init){
        try{
          let url = "";
          let method = "GET";
          if (typeof input === "string") {
            url = input;
          } else if (input && typeof input.url === "string") {
            url = input.url;
            method = (input.method || "GET").toUpperCase();
          }
          if (url && url.includes("/api/vsp/run_file_allow") && method === "GET") {
            const u = new URL(url, window.location.origin);
            const path = u.searchParams.get("path");
            if (!path) {
              u.searchParams.set("path", "run_gate_summary.json");
              const fixed = u.toString();
              // keep request shape minimal
              input = (typeof input === "string") ? fixed : fixed;
              try { console.debug("[VSP][P0] run_file_allow add default path =>", fixed); } catch(_){}
            }
          }
        } catch(_){}
        return origFetch(input, init);
      };
    })();
    /* ===================== /VSP_P0_RUNFILEALLOW_ENSURE_PATH_V1 ===================== */
    ''').strip("\n") + "\n"

    bundle.write_text(js + "\n\n" + fix, encoding="utf-8")
    print("[OK] appended bundle fix:", jmarker)
else:
    print("[OK] bundle already has:", jmarker)
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

if [ "$node_ok" = "1" ]; then
  node --check "$BUNDLE" && echo "[OK] node --check bundle OK"
fi

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
curl -fsS -I "$BASE/vsp5" | head -n 8
echo "== check endpoint rid_latest_gate_root =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 220; echo
echo "== check bundle marker =="
curl -fsS "$BASE/static/js/vsp_bundle_commercial_v2.js" | grep -n "VSP_P0_RUNFILEALLOW_ENSURE_PATH_V1" | head -n 3 || true

echo "[DONE] Hard refresh: Ctrl+Shift+R  $BASE/vsp5"
