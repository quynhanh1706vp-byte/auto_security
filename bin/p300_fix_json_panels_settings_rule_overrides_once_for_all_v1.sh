#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need ls

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p300_before_${TS}"
echo "[OK] backup current => ${F}.bak_p300_before_${TS}"

python3 - <<'PY'
from pathlib import Path
import subprocess, os, re, sys, time

F = Path("static/js/vsp_c_common_v1.js")

# 1) pick newest candidate that passes node --check
cands = [F] + sorted(F.parent.glob(F.name + ".bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

picked = None
for p in cands:
    try:
        r = subprocess.run(["node","--check",str(p)], capture_output=True, text=True)
        if r.returncode == 0:
            picked = p
            break
    except Exception:
        pass

if not picked:
    print("[ERR] cannot find any candidate passing `node --check`", file=sys.stderr)
    sys.exit(2)

if picked != F:
    F.write_text(picked.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print(f"[OK] restored base from: {picked}")

s = F.read_text(encoding="utf-8", errors="replace")

# 2) repair classic broken newline-in-string issues:
#    .split(" <newline> ")  => .split("\\n")   (i.e. JS sees "\n")
s0 = s

# fix split(" \n ")
s = re.sub(r'\.split\("\s*\n\s*"\)', r'.split("\\n")', s)
s = re.sub(r"\.split\('\s*\n\s*'\)", r".split('\\n')", s)

# fix accidental extra '")' right after split("\n")  e.g. split("\n")").length
s = re.sub(r'(\.split\("\\n"\))"\)', r'\1', s)
s = re.sub(r"(\\.split\\('\\\\n'\\))'\\)", r"\\1", s)

# also fix join(" \n ") just in case
s = re.sub(r'\.join\("\s*\n\s*"\)', r'.join("\\n")', s)
s = re.sub(r"\.join\('\s*\n\s*'\)", r".join('\\n')", s)

if s != s0:
    F.write_text(s, encoding="utf-8")
    print("[OK] repaired broken newline-in-string patterns")

# re-check after repair
r = subprocess.run(["node","--check",str(F)], capture_output=True, text=True)
if r.returncode != 0:
    print("[ERR] still failing node --check after repair", file=sys.stderr)
    print(r.stderr, file=sys.stderr)
    sys.exit(3)

# 3) install ONE final observer block (idempotent)
s = F.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P300_JSON_COLLAPSE_OBSERVER_V1"
if MARK in s:
    print("[OK] P300 already installed")
    sys.exit(0)

addon = r"""
/* ===================== VSP_P300_JSON_COLLAPSE_OBSERVER_V1 =====================
   Goal: Collapse ALL JSON <pre>/<code> blocks on /c/settings & /c/rule_overrides (and others)
   Durable: MutationObserver keeps it collapsed even after async re-render.
   Safe: Heuristic only wraps text that looks like JSON.
=============================================================================== */
(function(){
  try{
    if (window.__VSP_P300_JSON_COLLAPSE_OBSERVER_V1__) return;
    window.__VSP_P300_JSON_COLLAPSE_OBSERVER_V1__ = true;

    function now(){ return Date.now ? Date.now() : (new Date()).getTime(); }

    function looksLikeJsonText(t){
      if (!t) return false;
      var s = (""+t).trim();
      if (s.length < 2) return false;
      var c0 = s[0], c1 = s[s.length-1];
      if (!((c0 === "{" && c1 === "}") || (c0 === "[" && c1 === "]"))) return false;
      // reduce false positives: must contain ":" or "," for objects/arrays
      if (s.indexOf(":") < 0 && s.indexOf(",") < 0) return false;
      return true;
    }

    function countLines(t){
      try { return (""+t).split("\n").length; } catch(e){ return 0; }
    }

    function ensureCss(){
      if (document.getElementById("vsp_p300_json_css")) return;
      var st = document.createElement("style");
      st.id = "vsp_p300_json_css";
      st.textContent = `
        details.vsp-json-details{ margin: 6px 0; border: 1px solid rgba(255,255,255,0.08); border-radius: 10px; overflow: hidden; background: rgba(0,0,0,0.15); }
        details.vsp-json-details > summary{ cursor:pointer; user-select:none; padding: 10px 12px; font-size: 12px; color: rgba(255,255,255,0.85); background: rgba(255,255,255,0.03); }
        details.vsp-json-details[open] > summary{ background: rgba(255,255,255,0.06); }
        details.vsp-json-details pre, details.vsp-json-details code{ margin: 0; padding: 10px 12px; display:block; max-height: 360px; overflow:auto; }
      `;
      (document.head || document.documentElement).appendChild(st);
    }

    function isAlreadyWrapped(el){
      if (!el || !el.closest) return false;
      return !!el.closest("details.vsp-json-details");
    }

    function wrapJsonBlock(el){
      try{
        if (!el || !el.parentNode) return false;
        if (isAlreadyWrapped(el)) return false;

        var tag = (el.tagName || "").toUpperCase();
        if (tag !== "PRE" && tag !== "CODE") return false;

        var txt = el.textContent || "";
        if (!looksLikeJsonText(txt)) return false;

        ensureCss();

        var lines = countLines(txt);
        var details = document.createElement("details");
        details.className = "vsp-json-details";
        details.open = false; // always default collapsed

        var summary = document.createElement("summary");
        summary.textContent = "JSON (" + lines + " lines) — click to expand";
        details.appendChild(summary);

        // Move element into details
        var parent = el.parentNode;
        parent.insertBefore(details, el);
        details.appendChild(el);

        return true;
      }catch(e){
        return false;
      }
    }

    function collapseAll(root){
      try{
        root = root || document;
        // only run on commercial UI suite pages (but safe anyway)
        var path = (location && location.pathname) ? location.pathname : "";
        if (path.indexOf("/c/") !== 0) return;

        var nodes = root.querySelectorAll ? root.querySelectorAll("pre, code") : [];
        var changed = 0;
        for (var i=0;i<nodes.length;i++){
          if (wrapJsonBlock(nodes[i])) changed++;
        }
        return changed;
      }catch(e){
        return 0;
      }
    }

    function installObserver(){
      try{
        var mo = new MutationObserver(function(muts){
          var n = 0;
          for (var i=0;i<muts.length;i++){
            var m = muts[i];
            if (m.addedNodes && m.addedNodes.length){
              for (var j=0;j<m.addedNodes.length;j++){
                var a = m.addedNodes[j];
                if (!a) continue;
                if (a.nodeType === 1){
                  // element
                  n += collapseAll(a) || 0;
                }
              }
            }
          }
        });
        mo.observe(document.documentElement || document.body, {childList:true, subtree:true});
        window.__VSP_P300_JSON_MO__ = mo;
      }catch(e){}
    }

    function bootstrap(){
      // initial + re-run a few times in the first seconds (for async fetch)
      var t0 = now();
      var tries = 0;
      function tick(){
        tries++;
        collapseAll(document);
        if (tries < 20 && (now()-t0) < 6000){
          setTimeout(tick, 300);
        }
      }
      tick();
      installObserver();
    }

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", bootstrap);
    }else{
      bootstrap();
    }
    console.log("[VSP] installed P300 (global JSON collapse observer)");
  }catch(e){}
})();
"""
F.write_text(s + "\n" + addon + "\n", encoding="utf-8")
print("[OK] appended P300 into vsp_c_common_v1.js")

r = subprocess.run(["node","--check",str(F)], capture_output=True, text=True)
if r.returncode != 0:
    print("[ERR] node --check failed after append", file=sys.stderr)
    print(r.stderr, file=sys.stderr)
    sys.exit(4)

print("[OK] JS syntax OK (P300)")
PY

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
echo
echo "[ROLLBACK] if needed:"
echo "  cp -f ${F}.bak_p300_before_${TS} ${F} && node --check ${F}"
