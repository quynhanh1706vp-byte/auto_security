#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [A] ensure restart uses FULL gateway (not exportpdf_only) =="
R="/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh"
if [ -f "$R" ]; then
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$R" "$R.bak_fullgw_${TS}"
  echo "[BACKUP] $R.bak_fullgw_${TS}"

  # choose best available wsgi app
  APP=""
  for cand in \
    "wsgi_vsp_ui_gateway:application" \
    "wsgi_vsp_ui_gateway_exportpdf_force_v4:application" \
    "wsgi_vsp_ui_gateway_exportpdf_only:application"
  do
    MOD="${cand%%:*}"
    python3 - <<PY >/dev/null 2>&1
import importlib
m=importlib.import_module("${MOD}")
assert hasattr(m,"application")
PY
    if [ $? -eq 0 ]; then APP="$cand"; break; fi
  done

  if [ -z "$APP" ]; then
    echo "[WARN] cannot import any wsgi app; keep restart script as-is"
  else
    python3 - <<PY
from pathlib import Path
import re
p=Path("$R")
t=p.read_text(encoding="utf-8", errors="ignore")
t2=re.sub(r"wsgi_vsp_ui_gateway[^:]*:application", "$APP", t)
p.write_text(t2, encoding="utf-8")
print("[OK] restart_8910 now uses:", "$APP")
PY
  fi
else
  echo "[WARN] missing $R"
fi

echo
echo "== [B] restore datasource JS to a clean backup (node --check) and remove demo injections =="
F_DS="static/js/vsp_datasource_tab_v1.js"
[ -f "$F_DS" ] || { echo "[ERR] missing $F_DS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F_DS" "$F_DS.bak_before_repair_${TS}"
echo "[BACKUP] $F_DS.bak_before_repair_${TS}"

pick=""
for b in $(ls -1t ${F_DS}.bak_* 2>/dev/null || true); do
  cp -f "$b" /tmp/_ds_candidate.js
  # strip any demo block if exists
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("/tmp/_ds_candidate.js")
t=p.read_text(encoding="utf-8", errors="ignore")
t=re.sub(r"// === VSP_P2_DS_DEMO_BUTTON_V1 ===[\\s\\S]*?(?=\\n\\}|\\n\\)\\;|\\n// ===|\\Z)", "", t, count=1)
# also remove accidental escaped literal injection lines if any
t=t.replace("renderTable\\(root, items\\);", "renderTable(root, items);")
p.write_text(t, encoding="utf-8")
PY
  if node --check /tmp/_ds_candidate.js >/dev/null 2>&1; then
    pick="$b"
    break
  fi
done

if [ -n "$pick" ]; then
  cp -f "$pick" "$F_DS"
  echo "[OK] restored datasource from: $pick"
else
  echo "[WARN] no valid backup found; keep current but will try to clean it"
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_datasource_tab_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")
t=re.sub(r"// === VSP_P2_DS_DEMO_BUTTON_V1 ===[\\s\\S]*?(?=\\n\\}|\\n\\)\\;|\\n// ===|\\Z)", "", t, count=1)
t=t.replace("renderTable\\(root, items\\);", "renderTable(root, items);")
p.write_text(t, encoding="utf-8")
print("[OK] attempted cleanup current datasource js")
PY
fi

echo
echo "== [C] re-apply COMMERCIAL patches to datasource: root-guard + autorid + prefer PATH =="
# 1) root-guard ensureRoot
python3 - <<'PY'
from pathlib import Path
import re, sys
p=Path("static/js/vsp_datasource_tab_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")
if "// === VSP_P2_DATASOURCE_TABLE_V1 ===" not in t:
    print("[INFO] datasource table patch tag not found; leave as-is")
    sys.exit(0)

# patch ensureRoot() inside P2 block if present
idx=t.find("// === VSP_P2_DATASOURCE_TABLE_V1 ===")
head, tail = t[:idx], t[idx:]
pat=r"function ensureRoot\(\)\{[\s\S]*?\n  \}"
rep=r"""function ensureRoot(){
    let root =
         document.getElementById("vsp4-datasource")
      || document.getElementById("vsp-datasource-root")
      || document.getElementById("vsp-datasource-main")
      || document.querySelector("#vsp-tab-datasource-content")
      || document.querySelector("[data-tab-content='datasource']")
      || null;

    if (root){
      const tn = (root.tagName || "").toUpperCase();
      const role = (root.getAttribute && root.getAttribute("role")) || "";
      if (tn === "A" || tn === "BUTTON" || role === "tab") root = null;
    }

    if (!root){
      root = document.createElement("div");
      root.id = "vsp-datasource-root";
      const host =
           document.querySelector("#vsp4-main")
        || document.querySelector("#vsp-content")
        || document.body;
      host.appendChild(root);
    }
    if (!root.id) root.id = "vsp-datasource-root";
    return root;
  }"""
tail2, n = re.subn(pat, rep, tail, count=1)
if n==1:
    p.write_text(head+tail2, encoding="utf-8")
    print("[OK] root-guard ensureRoot patched")
else:
    print("[INFO] ensureRoot not patched (pattern mismatch) - ok")
PY

# 2) autorid + prefer PATH fetchFindings
python3 - <<'PY'
from pathlib import Path
import re, sys
p=Path("static/js/vsp_datasource_tab_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")
if "// === VSP_P2_DATASOURCE_TABLE_V1 ===" not in t:
    print("[INFO] no P2 datasource block; skip autorid/preferpath"); sys.exit(0)

if "// === VSP_P2_AUTORID_V1 ===" not in t:
    # insert autorid helper before fetchFindings
    needle="async function fetchFindings(filters){"
    pos=t.find(needle)
    if pos>0:
        inject=r'''
  // === VSP_P2_AUTORID_V1 ===
  let _vspLatestRidCache = null;
  async function resolveLatestRid(){
    if (_vspLatestRidCache) return _vspLatestRidCache;
    try{
      const r = await fetch("/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1", {cache:"no-store"});
      const j = await r.json();
      const rid = j?.items?.[0]?.run_id || j?.items?.[0]?.rid || j?.items?.[0]?.id || null;
      if (rid) _vspLatestRidCache = rid;
      return rid;
    }catch(e){ return null; }
  }
'''
        t=t[:pos]+inject+"\n"+t[pos:]

# replace fetchFindings with prefer-path version
pat=r"async function fetchFindings\(filters\)\{[\s\S]*?\n\s*\}"
new=r"""async function fetchFindings(filters){
    const f = Object.assign({}, (filters||{}));

    if (!f.rid && !f.run_id){
      const rid0 = (typeof resolveLatestRid === "function") ? await resolveLatestRid() : null;
      if (rid0) f.rid = rid0;
    }

    const rid = (f.rid || f.run_id || "").toString().trim();
    if (rid){
      delete f.rid; delete f.run_id;
      const q = buildQuery(f || {});
      const url = "/api/vsp/findings_preview_v1/" + encodeURIComponent(rid) + (q ? ("?"+q) : "");
      const r = await fetch(url, {cache:"no-store"});
      return await r.json();
    }

    const q = buildQuery(f || {});
    const url = "/api/vsp/findings_preview_v1" + (q ? ("?"+q) : "");
    const r = await fetch(url, {cache:"no-store"});
    return await r.json();
  }"""
t2, n = re.subn(pat, new, t, count=1)
if n==1:
    p.write_text(t2, encoding="utf-8")
    print("[OK] fetchFindings patched: autorid + prefer PATH")
else:
    p.write_text(t, encoding="utf-8")
    print("[WARN] fetchFindings not replaced (pattern mismatch); kept file")
PY

node --check static/js/vsp_datasource_tab_v1.js
echo "[OK] node --check datasource OK"

echo
echo "== [D] fix UI crash: null-guard for getElementById(...).innerHTML/textContent in vsp_ui_4tabs_commercial_v1.js =="
F_UI="static/js/vsp_ui_4tabs_commercial_v1.js"
if [ -f "$F_UI" ]; then
  cp -f "$F_UI" "$F_UI.bak_nullguard_${TS}"
  echo "[BACKUP] $F_UI.bak_nullguard_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")
TAG="// === VSP_P2_UI_NULL_GUARD_V2 ==="
if TAG not in t:
    helper=r'''
// === VSP_P2_UI_NULL_GUARD_V2 ===
(function(){
  window.VSP_EL_V2 = function(id){
    var el = document.getElementById(id);
    if (el) return el;
    var host = document.querySelector("#vsp4-main") ||
               document.querySelector("#vsp-content") ||
               document.body;
    el = document.createElement("div");
    el.id = id;
    host.appendChild(el);
    return el;
  };
})();
'''
    t = helper + "\n" + t

t = re.sub(r'document\.getElementById\(\s*["\']([^"\']+)["\']\s*\)\.innerHTML',
           r'window.VSP_EL_V2("\1").innerHTML', t)
t = re.sub(r'document\.getElementById\(\s*["\']([^"\']+)["\']\s*\)\.textContent',
           r'window.VSP_EL_V2("\1").textContent', t)

p.write_text(t, encoding="utf-8")
print("[OK] null-guard patched")
PY
  node --check "$F_UI"
  echo "[OK] node --check UI 4tabs OK"
else
  echo "[WARN] missing $F_UI"
fi

echo
echo "[DONE] Commercial real repair done."
echo "Next:"
echo "  /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh"
echo "  Ctrl+Shift+R"
echo "  open: http://127.0.0.1:8910/vsp4#tab=datasource&limit=200"
