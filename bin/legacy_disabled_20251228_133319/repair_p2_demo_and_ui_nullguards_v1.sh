#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [1] fix demo JSON (overwrite valid) =="
mkdir -p static/sample
cat > static/sample/findings_demo.json <<'JSON'
[
  {"severity":"HIGH","tool":"gitleaks","cwe":"CWE-798","title":"Hardcoded credential detected","file":"src/auth/login.py","line":42,"rule":"gitleaks.generic-api-key","fingerprint":"demo-1"},
  {"severity":"MEDIUM","tool":"semgrep","cwe":"CWE-79","title":"Potential XSS via unsanitized input","file":"web/views/profile.html","line":118,"rule":"javascript.lang.security.audit.xss","fingerprint":"demo-2"},
  {"severity":"LOW","tool":"kics","cwe":"CWE-200","title":"S3 bucket allows public read (IaC)","file":"iac/aws/s3.tf","line":9,"rule":"KICS.S3.PublicRead","fingerprint":"demo-3"},
  {"severity":"INFO","tool":"trivy-fs","cwe":"CWE-937","title":"Vulnerable dependency detected","file":"package-lock.json","line":1,"rule":"TRIVY.OSPKG","fingerprint":"demo-4"},
  {"severity":"HIGH","tool":"codeql","cwe":"CWE-22","title":"Path traversal in file download","file":"server/download.go","line":77,"rule":"go/path-injection","fingerprint":"demo-5","downgraded":true}
]
JSON
python3 - <<'PY'
import json
json.load(open("static/sample/findings_demo.json","r",encoding="utf-8"))
print("[OK] findings_demo.json valid")
PY

echo
echo "== [2] restore datasource JS from latest demo-btn backup (if any) =="
F_DS="static/js/vsp_datasource_tab_v1.js"
LATEST_BAK="$(ls -1t ${F_DS}.bak_demo_btn_* 2>/dev/null | head -n 1 || true)"
if [ -n "${LATEST_BAK}" ]; then
  cp -f "${LATEST_BAK}" "${F_DS}"
  echo "[OK] restored from ${LATEST_BAK}"
else
  echo "[WARN] no bak_demo_btn_* found; will patch in-place"
fi

echo
echo "== [3] inject demo button correctly (no regex backslashes) =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F_DS" "${F_DS}.bak_reinject_demo_${TS}"
echo "[BACKUP] ${F_DS}.bak_reinject_demo_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_datasource_tab_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_P2_DS_DEMO_BUTTON_V1 ==="
if TAG in t:
    print("[OK] demo button already present, skip")
    raise SystemExit(0)

needle = "renderTable(root, items);"
idx = t.find(needle)
if idx < 0:
    # fallback: if someone accidentally inserted escaped form, fix it first
    t = t.replace("renderTable\\(root, items\\);", "renderTable(root, items);")
    idx = t.find(needle)
if idx < 0:
    print("[ERR] cannot find renderTable(root, items); to hook"); raise SystemExit(2)

insert = r'''
renderTable(root, items);

// === VSP_P2_DS_DEMO_BUTTON_V1 ===
// If total=0, show "Load demo dataset" button to populate table (commercial demo)
try{
  if ((total === 0) && Array.isArray(items)) {
    const st = qs("#vsp-ds-status", root);
    if (st && !qs("#vsp-ds-demo-btn", root)) {
      const btn = document.createElement("button");
      btn.id = "vsp-ds-demo-btn";
      btn.className = "vsp-btn vsp-btn-ghost";
      btn.textContent = "Load demo dataset";
      btn.style.marginLeft = "10px";
      btn.addEventListener("click", async function(){
        try{
          const r = await fetch("/static/sample/findings_demo.json", {cache:"no-store"});
          const demo = await r.json();
          setStatus(root, "<b>Demo</b>: loaded " + (demo.length||0) + " items");
          renderTable(root, demo);
        }catch(e){
          setStatus(root, "<span style='color:#fca5a5;'>Demo load failed</span>");
        }
      });
      st.appendChild(btn);
    }
  }
}catch(_){}
'''
# replace first occurrence only
t = t.replace(needle, insert, 1)
p.write_text(t, encoding="utf-8")
print("[OK] demo button injected (correct)")
PY

node --check "$F_DS"
echo "[OK] node --check datasource JS OK"

echo
echo "== [4] patch vsp_ui_4tabs_commercial_v1.js to avoid null.innerHTML crash =="
F_UI="static/js/vsp_ui_4tabs_commercial_v1.js"
if [ -f "$F_UI" ]; then
  cp -f "$F_UI" "${F_UI}.bak_nullguard_${TS}"
  echo "[BACKUP] ${F_UI}.bak_nullguard_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_P2_UI_NULL_GUARD_V1 ==="
if TAG not in t:
    helper = r'''
// === VSP_P2_UI_NULL_GUARD_V1 ===
(function(){
  window.VSP_UI_SAFE_EL_V1 = function(id, parentSel){
    try{
      var el = document.getElementById(id);
      if (el) return el;
      var host = document.querySelector(parentSel || "#vsp4-main") ||
                 document.querySelector("#vsp-content") ||
                 document.body;
      el = document.createElement("div");
      el.id = id;
      host.appendChild(el);
      return el;
    }catch(e){
      var el2 = document.createElement("div");
      el2.id = id;
      document.body.appendChild(el2);
      return el2;
    }
  };
})();
'''
    t = helper + "\n" + t

# replace common crash pattern: document.getElementById("X").innerHTML/textContent
t = re.sub(r'document\.getElementById\(\s*["\']([^"\']+)["\']\s*\)\.innerHTML',
           r'window.VSP_UI_SAFE_EL_V1("\1").innerHTML', t)
t = re.sub(r'document\.getElementById\(\s*["\']([^"\']+)["\']\s*\)\.textContent',
           r'window.VSP_UI_SAFE_EL_V1("\1").textContent', t)

p.write_text(t, encoding="utf-8")
print("[OK] patched UI null-guards for getElementById(...).innerHTML/textContent")
PY

  node --check "$F_UI"
  echo "[OK] node --check UI 4tabs JS OK"
else
  echo "[SKIP] missing $F_UI"
fi

echo
echo "[DONE] Repair complete."
echo "Next:"
echo "  1) restart 8910"
echo "  2) hard refresh Ctrl+Shift+R"
echo "  3) open: http://127.0.0.1:8910/vsp4#tab=datasource&limit=200"
echo "     then click 'Load demo dataset' to see table"
