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
cp -f "$APP" "${APP}.bak_release_probe_${TS}"
cp -f "$JS"  "${JS}.bak_release_probe_${TS}"
echo "[BACKUP] ${APP}.bak_release_probe_${TS}"
echo "[BACKUP] ${JS}.bak_release_probe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RELEASE_PROBE_ALWAYS200_V1"
if marker not in s:
    block = textwrap.dedent(rf"""
    # ===================== {marker} =====================
    # 목적:
    #   - UI Release Card가 package 존재여부를 404 없이 확인하도록 probe API 제공
    #   - 항상 HTTP 200 + JSON으로 반환 (Log XHR 켜도 console đỏ 안 뜸)
    # 보안:
    #   - path는 out_ci/releases/ 아래만 허용
    #   - '..' 및 path traversal 차단
    # ====================================================

    from pathlib import Path as _Path
    from urllib.parse import urlparse as _urlparse

    @app.get("/api/vsp/release_probe")
    def vsp_release_probe():
        try:
            p = (request.args.get("path") or "").strip()
            u = (request.args.get("url") or "").strip()

            # prefer path; if url provided, use its pathname
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
                return jsonify({"ok": True, "exists": None, "allowed": False, "path": p})

            root = _Path(__file__).resolve().parent  # /home/test/Data/SECURITY_BUNDLE/ui
            cand = (root / p).resolve()

            # ensure within root
            if str(cand).startswith(str(root) + "/"):
                exists = cand.exists() and cand.is_file()
                size = cand.stat().st_size if exists else None
                return jsonify({"ok": True, "exists": bool(exists), "allowed": True, "path": p, "size": size})
            return jsonify({"ok": True, "exists": None, "allowed": False, "path": p})
        except Exception as e:
            # always 200
            return jsonify({"ok": True, "exists": None, "allowed": False, "err": str(e)[:200]})
    # ===================== /{marker} =====================
    """)

    # insert before if __name__ guard if possible
    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
    if m:
        s = s[:m.start()] + "\n" + block + "\n" + s[m.start():]
    else:
        s = s.rstrip() + "\n\n" + block + "\n"

    app.write_text(s, encoding="utf-8")
    print("[OK] injected:", marker)
else:
    print("[OK] already present:", marker)

# compile check
py_compile.compile(str(app), doraise=True)
print("[OK] py_compile:", app)
PY

python3 - <<'PY'
from pathlib import Path
import re

js = Path("static/js/vsp_runs_quick_actions_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")

# We patch ONLY the release-card existence check logic by appending a small override block.
# This keeps risk low and avoids large rewrites.
marker = "VSP_P1_RELEASE_CARD_USE_PROBE_NO404_V1"
if marker in s:
    print("[OK] already present:", marker)
    raise SystemExit(0)

patch = r"""
/* ===================== VSP_P1_RELEASE_CARD_USE_PROBE_NO404_V1 =====================
   목적: Release Card package 존재 여부를 HEAD/404 대신 probe API(200)로 확인하여 console đỏ(404)를 제거
   요구: backend /api/vsp/release_probe (always 200) 존재
================================================================================== */
(() => {
  // only if release card exists on page
  const card = document.getElementById("vsp_release_card_v2");
  if (!card) return;

  // monkey patch a helper used by our release card blocks: window.__vsp_release_exists_check
  // If earlier blocks already define it, we override to use probe.
  window.__vsp_release_exists_check = async (pkgUrl, timeoutMs) => {
    try{
      if (!pkgUrl) return { ok:true, exists:null, status:null, via:"PROBE" };
      let path = null;
      try{
        const u = new URL(String(pkgUrl), location.origin);
        path = (u.pathname || "");
      }catch(_){
        // if not a valid URL, try treat as path
        path = String(pkgUrl);
      }
      if (path && path.startsWith("/")) path = path.slice(1);

      const q = encodeURIComponent(path || "");
      const r = await fetch("/api/vsp/release_probe?path=" + q, { cache:"no-store", credentials:"same-origin" });
      // always 200; parse best-effort
      const j = await r.json().catch(()=>null);
      if (j && j.ok && j.allowed === true){
        if (j.exists === true) return { ok:true, exists:true, status:200, via:"PROBE" };
        if (j.exists === false) return { ok:true, exists:false, status:200, via:"PROBE" };
        return { ok:true, exists:null, status:200, via:"PROBE" };
      }
      // not allowed or unknown -> don't generate 404
      return { ok:true, exists:null, status:200, via:"PROBE" };
    }catch(e){
      return { ok:false, exists:null, status:null, via:"PROBE_ERR" };
    }
  };

  // Best-effort: if existing release card block stored a function named existsCheck in closure, we can't reach it.
  // But our V2/V2C blocks already call fetch(...) directly; so we add a tiny UX hint:
  // - If STALE detected, encourage manual Refresh.
  // (The real fix is to have the release card block call window.__vsp_release_exists_check if present.
  // To keep risk low, we additionally patch the file text to prefer this hook in those blocks below.)
})();
"""

# patch release card blocks to use hook if present
# Replace occurrences of: await existsCheck(pkgUrl, CFG.headTimeoutMs)
# with: await (window.__vsp_release_exists_check ? window.__vsp_release_exists_check(pkgUrl, CFG.headTimeoutMs) : existsCheck(pkgUrl, CFG.headTimeoutMs))
s2, n = re.subn(
    r'await\s+existsCheck\(([^,]+),\s*CFG\.headTimeoutMs\)',
    r'await (window.__vsp_release_exists_check ? window.__vsp_release_exists_check(\1, CFG.headTimeoutMs) : existsCheck(\1, CFG.headTimeoutMs))',
    s
)

js.write_text(s2.rstrip() + "\n\n" + patch.strip() + "\n", encoding="utf-8")
print("[OK] patched hook usage count=", n)
print("[OK] appended:", marker)
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

echo "[DONE] no404 probe patch applied"
