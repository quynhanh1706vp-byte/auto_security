#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p442_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need grep; need sed; need curl; need date; need head; need awk; need find; need xargs; need sudo || true

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/log.txt"; }

log "[INFO] BASE=$BASE SVC=$SVC OUT=$OUT"

# 0) Create helper JS to hide raw JSON panels (only on settings/rule_overrides, commercial or legacy)
mkdir -p static/js
HJS="static/js/vsp_hide_raw_json_panels_v1.js"
cat > "$HJS" <<'JS'
/* VSP_HIDE_RAW_JSON_PANELS_V1 */
(function(){
  function isTargetPage(){
    const p = (location.pathname||"");
    return (
      p === "/c/settings" || p === "/c/rule_overrides" ||
      p === "/settings"   || p === "/rule_overrides"
    );
  }
  function hidePanels(){
    if(!isTargetPage()) return;

    // 1) Hide panels whose heading text looks like raw JSON viewers
    const needles = [/raw\s*json/i, /live\s*view/i, /stable\s*json/i, /collapse/i];
    const nodes = Array.from(document.querySelectorAll("h1,h2,h3,h4,div,span,label,b,strong,summary"));
    for (const n of nodes){
      const t = (n.textContent||"").trim();
      if(!t) continue;
      if(!needles.some(r=>r.test(t))) continue;

      // climb to a reasonable container
      let cur = n;
      for(let i=0;i<8 && cur;i++){
        if(cur.classList && (cur.classList.contains("card") || cur.classList.contains("panel"))) break;
        if(cur.tagName && ["SECTION","ARTICLE"].includes(cur.tagName)) break;
        cur = cur.parentElement;
      }
      if(cur && cur.style){
        cur.style.display = "none";
      }
    }

    // 2) As a fallback: if there are <pre> blocks that look like huge JSON dumps on these pages, hide them
    const pres = Array.from(document.querySelectorAll("pre"));
    for(const pre of pres){
      const tx = (pre.textContent||"");
      if(tx.length > 300 && (tx.includes('{"') || tx.includes('"}') || tx.includes('"tools"') || tx.includes('"rules"'))){
        pre.style.display = "none";
      }
    }
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", hidePanels, {once:true});
  }else{
    hidePanels();
  }
})();
JS
log "[OK] wrote $HJS"

# 1) Patch templates: remove hard include of vsp_c_common_v1.js, ensure clean is present,
#    and allow legacy common only if ?legacy=1 (dynamic loader).
python3 - <<'PY'
from pathlib import Path
import re, datetime

root = Path(".")
tpl_dirs = []
for cand in ["templates", "ui/templates", "web/templates"]:
    p = root / cand
    if p.is_dir():
        tpl_dirs.append(p)

if not tpl_dirs:
    print("[ERR] templates/ not found"); raise SystemExit(2)

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

common_old = "vsp_c_common_v1.js"
common_clean = "vsp_c_common_clean_v1.js"
hide_js = "vsp_hide_raw_json_panels_v1.js"

patched = 0
targets = 0
hits_old = []

for d in tpl_dirs:
    for f in d.rglob("*.html"):
        s = f.read_text(encoding="utf-8", errors="replace")
        orig = s
        changed = False

        # backup once per file
        def backup():
            b = f.with_suffix(f.suffix + f".bak_p442_{ts}")
            if not b.exists():
                b.write_text(orig, encoding="utf-8", errors="replace")

        # remove any direct include of old common
        if common_old in s:
            hits_old.append(str(f))
            # remove full script tags referencing old common
            s2 = re.sub(r'(?is)\n?\s*<script[^>]+%s[^>]*>\s*</script>\s*' % re.escape(common_old), "\n", s)
            if s2 != s:
                s = s2
                changed = True

        # ensure clean common is present
        if common_clean not in s:
            # insert in <head> near end
            m = re.search(r'(?is)</head>', s)
            if m:
                ins = f'\n<script src="/static/js/{common_clean}?v={ts}"></script>\n'
                s = s[:m.start()] + ins + s[m.start():]
                changed = True

        # add dynamic legacy loader only when ?legacy=1, but only if template previously referenced old common
        # (to keep behavior minimal)
        if common_old in orig and "VSP_P442_LEGACY_COMMON_OPTIN" not in s:
            m = re.search(r'(?is)</head>', s)
            if m:
                dyn = f"""
<script>
/* VSP_P442_LEGACY_COMMON_OPTIN */
(function(){{
  try {{
    var q = new URLSearchParams(location.search||"");
    if(q.has("legacy")) {{
      var sc = document.createElement("script");
      sc.src = "/static/js/{common_old}?v={ts}";
      sc.defer = true;
      document.head.appendChild(sc);
      console.warn("[VSP] legacy common enabled via ?legacy=1");
    }}
  }} catch(e) {{}}
}})();
</script>
"""
                s = s[:m.start()] + dyn + s[m.start():]
                changed = True

        # On settings & rule_overrides pages, include hide-raw-json helper
        # (best-effort: based on filename keywords or body id markers)
        if re.search(r'(?i)(settings|rule_overrides)', f.name) or re.search(r'(?i)/c/(settings|rule_overrides)', s):
            if hide_js not in s:
                m = re.search(r'(?is)</head>', s)
                if m:
                    ins = f'\n<script src="/static/js/{hide_js}?v={ts}"></script>\n'
                    s = s[:m.start()] + ins + s[m.start():]
                    changed = True

        if changed and s != orig:
            backup()
            f.write_text(s, encoding="utf-8", errors="replace")
            patched += 1
        targets += 1

print("[OK] templates scanned =", targets)
print("[OK] templates patched =", patched)
print("[INFO] templates had old common =", len(hits_old))
PY

# 2) Restart & wait
log "[INFO] restarting $SVC"
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
else
  log "[WARN] systemctl not found; please restart service manually"
fi

ok=0
for i in $(seq 1 60); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.2
done
if [ "$ok" -ne 1 ]; then
  log "[ERR] UI not reachable after restart: $BASE/vsp5"
  exit 1
fi
log "[OK] UI reachable"

# 3) Proof checks: /c/settings & /c/rule_overrides HTML must NOT contain old common include
check_page(){
  local path="$1"
  local fn="$2"
  curl -fsS --max-time 5 "$BASE$path" -o "$OUT/$fn" || { log "[ERR] fetch $path failed"; return 1; }
  if grep -n "vsp_c_common_v1.js" "$OUT/$fn" >/dev/null; then
    log "[FAIL] $path still references vsp_c_common_v1.js"
    grep -n "vsp_c_common_v1.js" "$OUT/$fn" | head -n 5 | tee -a "$OUT/log.txt"
    return 1
  fi
  if ! grep -n "vsp_c_common_clean_v1.js" "$OUT/$fn" >/dev/null; then
    log "[FAIL] $path missing vsp_c_common_clean_v1.js"
    return 1
  fi
  log "[OK] $path uses CLEAN common only"
}

check_page "/c/settings" "BODY__c_settings.html"
check_page "/c/rule_overrides" "BODY__c_rule_overrides.html"
check_page "/runs" "BODY__runs.html"
check_page "/vsp5" "BODY__vsp5.html"

log "[DONE] P442 applied. Evidence in: $OUT"
