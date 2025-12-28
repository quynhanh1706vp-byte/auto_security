#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

APP="vsp_demo_app.py"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_release_probe_v2_${TS}"
cp -f "$JS"  "${JS}.bak_release_probe_v2_${TS}"
echo "[BACKUP] ${APP}.bak_release_probe_v2_${TS}"
echo "[BACKUP] ${JS}.bak_release_probe_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RELEASE_PROBE_ALWAYS200_V1"
if marker not in s:
    block = textwrap.dedent("""
    # ===================== {MARKER} =====================
    # Purpose:
    #   - Provide a probe API so UI can check release package existence without HEAD/404 noise
    #   - Always returns HTTP 200 + JSON
    # Security:
    #   - Only allow paths under out_ci/releases/
    #   - Block '..' and traversal
    # ====================================================

    from pathlib import Path as _Path
    from urllib.parse import urlparse as _urlparse

    @app.get("/api/vsp/release_probe")
    def vsp_release_probe():
        try:
            p = (request.args.get("path") or "").strip()
            u = (request.args.get("url") or "").strip()

            if (not p) and u:
                try:
                    pu = _urlparse(u)
                    p = (pu.path or "").strip()
                except Exception:
                    p = ""

            if p.startswith("/"):
                p = p[1:]

            # strict allowlist (runs-only release packages)
            if (not p) or (".." in p) or (not p.startswith("out_ci/releases/")):
                return jsonify({{"ok": True, "exists": None, "allowed": False, "path": p}})

            root = _Path(__file__).resolve().parent  # /home/test/Data/SECURITY_BUNDLE/ui
            cand = (root / p).resolve()

            # ensure within root
            if str(cand).startswith(str(root) + "/"):
                exists = cand.exists() and cand.is_file()
                size = cand.stat().st_size if exists else None
                return jsonify({{"ok": True, "exists": bool(exists), "allowed": True, "path": p, "size": size}})

            return jsonify({{"ok": True, "exists": None, "allowed": False, "path": p}})
        except Exception as e:
            # always 200
            return jsonify({{"ok": True, "exists": None, "allowed": False, "err": str(e)[:200]}})

    # ===================== /{MARKER} =====================
    """).replace("{MARKER}", marker)

    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
    if m:
        s = s[:m.start()] + "\n" + block + "\n" + s[m.start():]
    else:
        s = s.rstrip() + "\n\n" + block + "\n"

    app.write_text(s, encoding="utf-8")
    print("[OK] injected:", marker)
else:
    print("[OK] already present:", marker)

py_compile.compile(str(app), doraise=True)
print("[OK] py_compile:", app)
PY

python3 - <<'PY'
from pathlib import Path
import re

js = Path("static/js/vsp_runs_quick_actions_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")

# Fix any accidental "None" in JS from earlier patches
s = s.replace("last.exists = None;", "last.exists = null;")

# Ensure release card blocks (if present) prefer window hook instead of direct existsCheck()
# Patch both common forms.
patterns = [
  r'await\s+existsCheck\(([^,]+),\s*CFG\.headTimeoutMs\)',
  r'await\s+existsCheck\(([^)]+)\)'
]
for pat in patterns:
    s, _ = re.subn(
        pat,
        r'await (window.__vsp_release_exists_check ? window.__vsp_release_exists_check(\1, CFG.headTimeoutMs) : existsCheck(\1, CFG.headTimeoutMs))',
        s
    )

marker = "VSP_P1_RELEASE_CARD_USE_PROBE_NO404_V2"
if marker not in s:
    hook = r"""
/* ===================== VSP_P1_RELEASE_CARD_USE_PROBE_NO404_V2 =====================
   - Use backend probe (always 200) to avoid console red 404 when DevTools logs XHR
   - Backend: /api/vsp/release_probe?path=out_ci/releases/...
================================================================================== */
(() => {
  if (window.__vsp_release_probe_no404_v2) return;
  window.__vsp_release_probe_no404_v2 = true;

  window.__vsp_release_exists_check = async (pkgUrl, timeoutMs) => {
    try{
      if (!pkgUrl) return { ok:true, exists:null, status:200, via:"PROBE" };

      let path = "";
      try{
        const u = new URL(String(pkgUrl), location.origin);
        path = (u.pathname || "");
      }catch(_){
        path = String(pkgUrl || "");
      }
      if (path.startsWith("/")) path = path.slice(1);

      const r = await fetch("/api/vsp/release_probe?path=" + encodeURIComponent(path), {
        cache:"no-store",
        credentials:"same-origin"
      });
      const j = await r.json().catch(()=>null);

      if (j && j.ok === true && j.allowed === true){
        if (j.exists === true)  return { ok:true, exists:true,  status:200, via:"PROBE" };
        if (j.exists === false) return { ok:true, exists:false, status:200, via:"PROBE" };
        return { ok:true, exists:null, status:200, via:"PROBE" };
      }
      return { ok:true, exists:null, status:200, via:"PROBE" };
    }catch(e){
      return { ok:false, exists:null, status:null, via:"PROBE_ERR" };
    }
  };
})();
"""
    s = s.rstrip() + "\n\n" + hook.strip() + "\n"
    print("[OK] appended:", marker)
else:
    print("[OK] already present:", marker)

js.write_text(s, encoding="utf-8")
print("[OK] wrote:", js)
PY

if [ "$node_ok" -eq 1 ]; then
  echo "== node --check =="
  node --check "$JS"
else
  echo "[WARN] node not found; skip syntax check"
fi

echo "== restart service (best-effort) =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1

echo "[DONE] release probe no404 v2 applied"
