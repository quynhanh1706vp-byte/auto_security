#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }

# 1) Rewrite vsp_c_dashboard_v1.js with RID sanitizer + always prefer latest RID if URL/localStorage invalid
F="static/js/vsp_c_dashboard_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_p116d_${TS}"
ok "backup: ${F}.bak_p116d_${TS}"

cat > "$F" <<'JS'
/* VSP_P116D_RID_SANITIZE_AUTOLATEST_V1 */
(() => {
  const $ = (sel) => document.querySelector(sel);

  function qparam(name){
    try { return new URLSearchParams(location.search).get(name); } catch(e){ return null; }
  }
  function setText(id, v){
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = (v === null || v === undefined) ? "" : String(v);
  }

  function isValidRid(r){
    if (!r) return false;
    r = String(r).trim();
    if (!r) return false;

    // reject obvious junk
    const bad = ["FILL_REAL_DATA", ".js", ".css", "VSP_FILL_", "TABS_P1_V1"];
    const up = r.toUpperCase();
    if (bad.some(x => up.includes(x))) return false;

    // accept common real run ids
    if (/^(VSP_CI_\d{8}_\d{6})$/.test(r)) return true;
    if (/^(RUN_)/.test(r) && /\d/.test(r) && r.length > 12) return true;
    if (/^(RUN_VSP_)/.test(r) && /\d/.test(r)) return true;

    // generic: must start with VSP_ or RUN_ and contain digits, only safe chars
    if (!/^(VSP_|RUN_)/.test(r)) return false;
    if (!/\d/.test(r)) return false;
    if (!/^[A-Za-z0-9_:-]+$/.test(r)) return false;
    return true;
  }

  async function fetchJson(url){
    const r = await fetch(url, { credentials: "same-origin" });
    const t = await r.text();
    let j=null; try{ j=JSON.parse(t); }catch(e){}
    return { ok:r.ok, status:r.status, json:j, text:t };
  }

  async function resolveRid(){
    // 0) URL rid
    let rid = qparam("rid");
    if (rid !== null) rid = (rid || "").trim();
    if (isValidRid(rid)) return rid;

    // if URL had invalid rid, remove it (avoid loops)
    if (rid !== null && rid && !isValidRid(rid)) {
      try {
        const u = new URL(location.href);
        u.searchParams.delete("rid");
        location.replace(u.toString());
        return null;
      } catch(e) {}
    }

    // 1) Latest from API (preferred)
    const runs = await fetchJson(`/api/ui/runs_v3?limit=1&include_ci=1`);
    const latest = (runs?.json?.items?.[0]?.rid || "").trim();
    if (isValidRid(latest)) return latest;

    // 2) localStorage (only if valid)
    try {
      const last = (localStorage.getItem("vsp_rid") || "").trim();
      if (isValidRid(last)) return last;
      if (last && !isValidRid(last)) localStorage.removeItem("vsp_rid");
    } catch(e){}

    return "";
  }

  // minimal render: show RID + status; other modules can fill the rest
  async function main(){
    const rid = await resolveRid();
    if (rid === null) return; // redirected

    // persist only if valid
    if (isValidRid(rid)) {
      try { localStorage.setItem("vsp_rid", rid); } catch(e){}
      try { window.VSP_RID = rid; } catch(e){}
    }

    // if URL missing rid, add it (stable deep link)
    try {
      const u = new URL(location.href);
      const cur = (u.searchParams.get("rid") || "").trim();
      if (!cur && isValidRid(rid)) {
        u.searchParams.set("rid", rid);
        location.replace(u.toString());
        return;
      }
    } catch(e){}

    setText("p-rid", rid || "(no rid)");
    setText("k-status", rid ? "OK" : "DEGRADED");

    // refresh button bypass
    const br = document.getElementById("b-refresh");
    if (br && !br.dataset.p116d){
      br.dataset.p116d="1";
      br.addEventListener("click", () => {
        const u = new URL(location.href);
        u.searchParams.set("nocache","1");
        location.href = u.toString();
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", main);
  } else {
    main();
  }
})();
JS

ok "wrote $F"

# 2) Guard fill_real_data script from writing bad RID into localStorage (best-effort)
python3 - <<'PY'
from pathlib import Path
import re, datetime

f = Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
if not f.exists():
    print("[WARN] missing vsp_fill_real_data_5tabs_p1_v1.js (skip guard)")
    raise SystemExit(0)

s = f.read_text(encoding="utf-8", errors="replace")
mark="VSP_P116D_GUARD_SET_VSP_RID"
if mark in s:
    print("[OK] fill_real_data guard already present")
    raise SystemExit(0)

bak = f.with_suffix(f.suffix + f".bak_p116d_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}")
bak.write_text(s, encoding="utf-8")
print("[OK] backup:", bak)

# Replace localStorage.setItem('vsp_rid', X) with guarded version
pat = re.compile(r'localStorage\.setItem\(\s*[\'"]vsp_rid[\'"]\s*,\s*([^)]+)\)\s*;')
def repl(m):
    expr = m.group(1)
    return (
        f"// {mark}\n"
        f"try {{\n"
        f"  var __rid = ({expr});\n"
        f"  var __s = String(__rid||'');\n"
        f"  if (__s && !/FILL_REAL_DATA|\\.js|\\.css/i.test(__s) && /^(VSP_|RUN_)/.test(__s) && /\\d/.test(__s)) {{\n"
        f"    localStorage.setItem('vsp_rid', __s);\n"
        f"  }}\n"
        f"}} catch(e) {{}}\n"
    )
s2, n = pat.subn(repl, s, count=0)
if n == 0:
    # if not found, just add a note shim at top (do nothing)
    s2 = "// " + mark + " (no vsp_rid setItem found)\n" + s
    print("[WARN] no localStorage.setItem('vsp_rid', ...) found; added marker only")
else:
    print("[OK] guarded", n, "setItem calls")
f.write_text(s2, encoding="utf-8")
print("[OK] patched:", f)
PY

echo
ok "P116d applied."
echo "[NEXT] Open: http://127.0.0.1:8910/c/dashboard  then Hard refresh (Ctrl+Shift+R)"
