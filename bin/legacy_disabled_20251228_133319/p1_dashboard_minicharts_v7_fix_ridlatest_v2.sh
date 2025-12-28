#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_v7ridlatest_v2_${TS}"
echo "[BACKUP] ${JS}.bak_v7ridlatest_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASH_MINICHARTS_V7_ONLY_SAFE_V1"
mi = s.find(marker)
if mi < 0:
    raise SystemExit("[ERR] V7 marker not found. Apply v7_only first.")

# Work in a bounded window after marker (avoid patching unrelated parts)
win_start = max(0, mi - 200)  # include comment header a bit
win_end = min(len(s), mi + 60000)
win = s[win_start:win_end]

# locate getRID function
m = re.search(r"function\s+getRID\s*\(\)\s*\{", win)
if not m:
    raise SystemExit("[ERR] getRID() not found in V7 window.")
func_start = m.start()

# find matching closing brace for getRID using a small JS brace parser
i = func_start
brace = 0
in_s = in_d = in_t = False
esc = False
while i < len(win):
    ch = win[i]
    if esc:
        esc = False
        i += 1
        continue
    if ch == "\\":
        # escape inside strings/templates
        if in_s or in_d or in_t:
            esc = True
        i += 1
        continue
    if in_s:
        if ch == "'": in_s = False
        i += 1
        continue
    if in_d:
        if ch == '"': in_d = False
        i += 1
        continue
    if in_t:
        if ch == "`": in_t = False
        i += 1
        continue
    # not inside string
    if ch == "'":
        in_s = True; i += 1; continue
    if ch == '"':
        in_d = True; i += 1; continue
    if ch == "`":
        in_t = True; i += 1; continue

    if ch == "{":
        brace += 1
    elif ch == "}":
        brace -= 1
        if brace == 0:
            # include this closing brace
            func_end = i + 1
            break
    i += 1
else:
    raise SystemExit("[ERR] could not parse getRID() braces.")

old_func = win[func_start:func_end]

new_getrid = """
function getRID(){
  try{
    var u = new URL(location.href);
    var rid = u.searchParams.get("rid") || u.searchParams.get("RID") || "";
    rid = (rid||"").trim();
    if (rid && rid !== "YOUR_RID") return rid;
  }catch(e){}
  // cached/global
  try{
    var cr = (window.__VSP_RID||"").toString().trim();
    if (cr && cr !== "YOUR_RID") return cr;
  }catch(e){}
  // bounded DOM sniff
  try{
    var chips = Array.prototype.slice.call(document.querySelectorAll("a,button,span,div"), 0, 160);
    for(var i=0;i<chips.length;i++){
      var t=(chips[i].textContent||"").trim();
      if(t.startsWith("VSP_") && t.length<80 && t!=="YOUR_RID") return t;
      if(t.indexOf("RID:")>=0){
        var mm=t.match(/RID:\\s*([A-Za-z0-9_:-]{6,80})/);
        if(mm && mm[1] && mm[1]!=="YOUR_RID") return mm[1];
      }
    }
  }catch(e){}
  return "";
}
""".strip()

# replace function text by slicing (no re.sub template issues)
win2 = win[:func_start] + new_getrid + win[func_end:]

# insert fetchRidLatest() right after getRID() if missing
if "async function fetchRidLatest" not in win2:
    insert_after = win2.find(new_getrid) + len(new_getrid)
    fetch_rid_latest = """
async function fetchRidLatest(){
  var ctrl = new AbortController();
  var to = setTimeout(function(){ try{ctrl.abort();}catch(e){} }, 1500);
  try{
    var r = await fetch("/api/vsp/rid_latest", {credentials:"same-origin", signal: ctrl.signal});
    var j = await r.json().catch(function(){ return null; });
    var rid = (j && (j.rid||j.RID) || "").toString().trim();
    if (rid && rid !== "YOUR_RID") return rid;
  }catch(e){}
  finally{ clearTimeout(to); }
  return "";
}
""".strip()
    win2 = win2[:insert_after] + "\n\n" + fetch_rid_latest + "\n\n" + win2[insert_after:]

# patch main flow: rid fallback to rid_latest when missing/YOUR_RID
needle = "var rid = getRID();"
if needle in win2:
    win2 = win2.replace(
        needle,
        "var rid = getRID();\n  if(!rid || rid==='YOUR_RID'){ try{ rid = await fetchRidLatest() || rid; }catch(e){} }",
        1
    )

# avoid appending rid=YOUR_RID
win2 = win2.replace('if(rid) u += "&rid=" + encodeURIComponent(rid);',
                    'if(rid && rid!=="YOUR_RID") u += "&rid=" + encodeURIComponent(rid);')

# write back
s_new = s[:win_start] + win2 + s[win_end:]
p.write_text(s_new, encoding="utf-8")
print("[OK] V7 patched: auto rid_latest when rid missing/YOUR_RID (slice-based, safe)")
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS"; exit 2; }

echo "[DONE] Ctrl+Shift+R then open: http://127.0.0.1:8910/vsp5"
