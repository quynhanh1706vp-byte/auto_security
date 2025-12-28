#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need ls; need head; need sed; need grep

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BK="${F}.bak_p306_before_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup current => $BK"

ok_check(){
  node --check "$1" >/dev/null 2>&1
}

echo "== [1] find a JS candidate that passes node --check (prefer newest backups) =="
CAND=""
# candidates: newest backups first, then current file last
mapfile -t backups < <(ls -1t "${F}".bak_* 2>/dev/null || true)
for c in "${backups[@]}"; do
  if ok_check "$c"; then
    CAND="$c"
    break
  fi
done
if [ -z "$CAND" ]; then
  if ok_check "$F"; then
    CAND="$F"
  fi
fi

if [ -z "$CAND" ]; then
  echo "[ERR] No candidate passes node --check (including backups)."
  echo "[HINT] We'll try a minimal surgical repair for common broken patterns..."
  python3 - <<'PY'
from pathlib import Path
import re, sys, subprocess

p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Fix common accidental extra quote+paren after split("\n")
fixes = [
  (r'split\("\\n"\)\)"', r'split("\\n")'),
  (r'split\("\\n"\)\)"\)', r'split("\\n")'),
  (r'split\("\\n"\)\)"\)\.', r'split("\\n").'),
  (r'split\("\\n"\)\)"\)\.length', r'split("\\n").length'),
  (r'split\("\\n"\)\)"\)\.length', r'split("\\n").length'),
  (r'split\("\\n"\)\)"\)\s*\.length', r'split("\\n").length'),
  (r'split\("\\n"\)\)"\)\s*;', r'split("\\n");'),
  (r'split\("\\n"\)\)"\)', r'split("\\n")'),
  (r'split\("\\n"\)\)"', r'split("\\n")'),
]
before=s
for pat, rep in fixes:
  s=re.sub(pat, rep, s)

# Fix an unterminated split(" <newline>  ... ) case: replace split(" + newline with split("\\n")
s=re.sub(r'split\(\s*"\s*\n\s*"\s*\)', r'split("\\n")', s)

# Also fix the very common broken literal: txt.split(" + newline
s=re.sub(r'(split\()\s*"\s*\n', r'\1"\\n"', s)

if s==before:
  print("[INFO] no surgical patterns matched (file may be broken differently).")
else:
  p.write_text(s, encoding="utf-8")
  print("[OK] applied surgical fixes into vsp_c_common_v1.js")

# validate
try:
  subprocess.check_call(["node","--check",str(p)])
  print("[OK] node --check now passes after surgical repair")
except subprocess.CalledProcessError:
  print("[ERR] still failing node --check after surgical repair")
  sys.exit(3)
PY
  echo "== [1b] after surgical repair: using current file as candidate =="
  CAND="$F"
else
  echo "[OK] picked candidate: $CAND"
  if [ "$CAND" != "$F" ]; then
    cp -f "$CAND" "$F"
    echo "[OK] restored $F from $CAND"
  else
    echo "[OK] keep current $F (already valid)"
  fi
fi

echo "== [2] inject ONE clean JSON collapse observer block (Settings + Rule Overrides) =="
python3 - <<'PY'
from pathlib import Path
import re, subprocess, sys

p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_P306_JSON_COLLAPSE_OBSERVER_BEGIN */"
END  ="/* VSP_P306_JSON_COLLAPSE_OBSERVER_END */"

block = r'''
/* VSP_P306_JSON_COLLAPSE_OBSERVER_BEGIN */
(function(){
  try{
    if (window.__VSP_P306_JSON_OBSERVER_INSTALLED) return;
    window.__VSP_P306_JSON_OBSERVER_INSTALLED = true;

    function onTargetPage(){
      try{
        var path = (location && location.pathname) ? location.pathname : "";
        return (path.indexOf("/c/settings")>=0) || (path.indexOf("/c/rule_overrides")>=0) ||
               (path.indexOf("/settings")>=0) || (path.indexOf("/rule_overrides")>=0);
      }catch(e){ return true; }
    }

    function isJsonLike(txt){
      if(!txt) return false;
      var t = (""+txt).trim();
      if(t.length < 2) return false;
      var c0 = t[0], c1 = t[t.length-1];
      if(!((c0==="{" && c1==="}") || (c0==="[" && c1==="]"))) return false;
      // quick reject if looks like HTML
      if(t.indexOf("<html")>=0 || t.indexOf("<!DOCTYPE")>=0) return false;
      return true;
    }

    function lineCount(txt){
      // robust across \n / \r\n
      return (""+txt).split(/\r?\n/).length;
    }

    function collapseOnePre(pre){
      if(!pre || !pre.parentNode) return;
      if(pre.dataset && pre.dataset.vspJsonCollapsed==="1") return;
      if(pre.closest && pre.closest("details")) return;

      var txt = pre.textContent || "";
      if(!isJsonLike(txt)) return;

      var lines = lineCount(txt);
      if(lines < 6) return; // avoid collapsing tiny JSON

      var details = document.createElement("details");
      details.className = "vsp-json-details";
      details.style.cssText = "margin:0; padding:0;";

      var summary = document.createElement("summary");
      summary.className = "vsp-json-summary";
      summary.textContent = "JSON (" + lines + " lines) — click to expand";
      summary.style.cssText = "cursor:pointer; user-select:none; opacity:.85; padding:6px 8px; border-radius:10px;";

      details.appendChild(summary);
      pre.parentNode.insertBefore(details, pre);
      details.appendChild(pre);

      if(pre.dataset) pre.dataset.vspJsonCollapsed="1";
      details.open = false;
    }

    function scan(root){
      if(!onTargetPage()) return;
      var scope = root || document;
      var pres = [];
      try{
        pres = scope.querySelectorAll ? scope.querySelectorAll("pre") : [];
      }catch(e){ pres = []; }
      for(var i=0;i<pres.length;i++){
        collapseOnePre(pres[i]);
      }
    }

    var timer = null;
    function scheduleScan(root){
      if(timer) return;
      timer = setTimeout(function(){
        timer = null;
        scan(root);
      }, 80);
    }

    // initial
    scheduleScan(document);

    // keep collapsing even if tab JS re-renders JSON later
    var obs = new MutationObserver(function(muts){
      // fast exit
      if(!onTargetPage()) return;
      scheduleScan(document);
    });
    obs.observe(document.documentElement || document.body, {subtree:true, childList:true, characterData:true});

    window.addEventListener("hashchange", function(){ scheduleScan(document); });
    window.addEventListener("popstate", function(){ scheduleScan(document); });
    document.addEventListener("visibilitychange", function(){ scheduleScan(document); });

    console.log("[VSP] installed P306 (global JSON collapse observer: settings + rule_overrides)");
  }catch(e){
    console.warn("[VSP] P306 install failed:", e);
  }
})();
 /* VSP_P306_JSON_COLLAPSE_OBSERVER_END */
'''.strip("\n") + "\n"

if BEGIN in s and END in s:
  s = re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), block, s, flags=re.S)
else:
  s = s.rstrip() + "\n\n" + block

p.write_text(s, encoding="utf-8")

# validate
try:
  subprocess.check_call(["node","--check",str(p)])
except subprocess.CalledProcessError:
  print("[ERR] node --check fails after injecting P306")
  sys.exit(4)

print("[OK] injected P306 into vsp_c_common_v1.js and node --check OK")
PY

echo "== [3] done =="
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
echo ""
echo "[TIP] If still expands back after a second, open console and confirm you see:"
echo "  [VSP] installed P306 (global JSON collapse observer: settings + rule_overrides)"
echo ""
echo "[ROLLBACK] cp -f \"$BK\" \"$F\" && node --check \"$F\""
