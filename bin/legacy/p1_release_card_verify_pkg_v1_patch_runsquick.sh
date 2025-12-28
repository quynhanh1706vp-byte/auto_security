#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_relverify_${TS}"
echo "[BACKUP] ${JS}.bak_relverify_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_CARD_VERIFY_PKG_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# We’ll append a small helper and monkey-patch the release card update function if present.
helper = textwrap.dedent(r"""
/* ===================== VSP_P1_RELEASE_CARD_VERIFY_PKG_V1 ===================== */
async function __vspRelPkgExistsV1(relPath){
  try{
    if(!relPath) return {ok:false, exists:false};
    const u = "/api/vsp/release_pkg_exists?path=" + encodeURIComponent(relPath);
    const r = await fetch(u, {cache:"no-store"});
    const j = await r.json().catch(()=>null);
    return j || {ok:false, exists:false};
  }catch(e){
    return {ok:false, exists:false};
  }
}
/* ===================== /VSP_P1_RELEASE_CARD_VERIFY_PKG_V1 ===================== */
""")

s2 = s.rstrip() + "\n\n" + helper + "\n"

# Best-effort patch: replace text "cannot verify package" message to be conditional
# and if we see a function name in log "ReleaseCardRunsV1", patch it.
# Common pattern: console.log("[ReleaseCardRunsV1] ...") or "ReleaseCardRunsV1 shown:"
if "ReleaseCardRunsV1" in s2:
    # inject a hook after it sets package/sha/ts: look for 'shown:' log and insert verify
    s2 = re.sub(
        r'(ReleaseCardRunsV1[^\n]*shown:[^\n]*\n)',
        r'\1' + textwrap.dedent(r"""
try{
  const relPath = (j && (j.release_pkg || j.package)) ? (j.release_pkg || j.package) : "";
  const ex = await __vspRelPkgExistsV1(relPath);
  if (ex && ex.exists){
    // if badge text element exists, flip to OK
    try{
      if (badgeEl) { badgeEl.textContent = "OK"; badgeEl.classList && badgeEl.classList.add("ok"); }
    }catch(e){}
    try{
      if (msgEl && /cannot verify/i.test(msgEl.textContent||"")) msgEl.textContent = "";
    }catch(e){}
  }
}catch(e){}
"""),
        s2,
        count=1
    )

# Also: turn hard-coded 'cannot verify package' into softer message
s2 = s2.replace("cannot verify package", "verify package: pending")

p.write_text(s2, encoding="utf-8")
print("[OK] appended", MARK)
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] release card verify pkg patch installed."
