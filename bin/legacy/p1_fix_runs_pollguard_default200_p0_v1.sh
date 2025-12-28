#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

MARK="VSP_P0_MKJSONRESPONSE_DEFAULT200_V1"
NEW_FUNC = r'''
  // VSP_P0_MKJSONRESPONSE_DEFAULT200_V1
  function mkJsonResponse(obj, status){
    // IMPORTANT: cached/backoff responses must NOT default to 503 (it causes UI flicker FAIL<->OK)
    const st = (typeof status === "number") ? status : 200;
    try {
      return new Response(JSON.stringify(obj), {
        status: st,
        headers: {
          "Content-Type":"application/json; charset=utf-8",
          "X-VSP-CACHED":"1",
          "X-VSP-GUARD":"1"
        }
      });
    } catch(e) {
      // response-like fallback (keep status 200 by default)
      return { ok: !!(obj && obj.ok), status: st, json: async()=>obj };
    }
  }
'''.strip("\n")

def patch_text(s: str):
    if MARK in s:
        return s, 0

    # Replace classic function mkJsonResponse(obj, status){ ... }
    # We replace whole function body to avoid missing other "status||503" variants.
    pat = re.compile(r'(^[ \t]*function[ \t]+mkJsonResponse[ \t]*\([^\)]*\)[ \t]*\{)(?:.|\n)*?(^[ \t]*\})',
                     re.M)
    m = pat.search(s)
    if m:
        # Keep indentation similar to original (use indent from "function" line)
        func_line = m.group(1)
        indent = re.match(r'^([ \t]*)', func_line).group(1)
        repl = "\n".join(indent + line if line.strip() else line for line in NEW_FUNC.splitlines())
        s2 = pat.sub(repl, s, count=1)
        return s2, 1

    # Replace arrow/const forms if any: const mkJsonResponse = (obj,status)=>{...}
    pat2 = re.compile(r'(^[ \t]*(?:const|let|var)[ \t]+mkJsonResponse[ \t]*=[ \t]*\([^\)]*\)[ \t]*=>[ \t]*\{)(?:.|\n)*?(^[ \t]*\}[ \t]*;?)',
                      re.M)
    m2 = pat2.search(s)
    if m2:
        indent = re.match(r'^([ \t]*)', m2.group(1)).group(1)
        # convert to function form to be deterministic
        repl = "\n".join(indent + line if line.strip() else line for line in NEW_FUNC.splitlines())
        s2 = pat2.sub(repl, s, count=1)
        return s2, 1

    # As fallback: patch ONLY the dangerous default "status||503" to default 200
    n = 0
    s2, k = re.subn(r'status\s*:\s*status\s*\|\|\s*503', 'status: ((typeof status==="number")?status:200)', s)
    n += k
    s2, k = re.subn(r'status\s*:\s*status\s*\|\|\s*502', 'status: ((typeof status==="number")?status:200)', s2)
    n += k
    s2, k = re.subn(r'status\s*:\s*status\s*\|\|\s*500', 'status: ((typeof status==="number")?status:200)', s2)
    n += k
    if n>0 and MARK not in s2:
        s2 = s2 + "\n/* "+MARK+" (fallback-subst) */\n"
    return s2, n

roots = [Path("templates"), Path("static/js")]
targets = []
for r in roots:
    if r.exists():
        targets += list(r.rglob("*.html")) + list(r.rglob("*.js"))

changed = 0
patched_files = []
for p in targets:
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    s2, n = patch_text(s)
    if n>0:
        bak = p.with_suffix(p.suffix + f".bak_mkjson200_{time.strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(s, encoding="utf-8")
        p.write_text(s2, encoding="utf-8")
        changed += 1
        patched_files.append(str(p))

print(f"[OK] patched_files={changed}")
for f in patched_files[:60]:
    print(" -", f)
if changed==0:
    print("[WARN] nothing patched (maybe already fixed or mkJsonResponse not found in scanned files).")
PY

# sanity check JS syntax if possible
for f in static/js/vsp_bundle_commercial_v2.js static/js/vsp_runs_tab_resolved_v1.js static/js/vsp_app_entry_safe_v1.js; do
  [ -f "$f" ] && command -v node >/dev/null 2>&1 && node --check "$f" && echo "[OK] node --check: $f" || true
done

echo "[NEXT] restart UI then hard refresh /runs"
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
