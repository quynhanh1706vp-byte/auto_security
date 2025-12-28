#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== REBUILD COMMERCIAL BUNDLE V2 (P0 v2) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

OUT="static/js/vsp_bundle_commercial_v2.js"
mkdir -p static/js out_ci templates

# (0) restore router if it was stubbed
restore_if_stub() {
  local F="$1"
  [ -f "$F" ] || return 0
  if grep -q "STUB (COMMERCIAL" "$F" 2>/dev/null; then
    local B
    B="$(ls -1t "${F}.bak_stub_"* 2>/dev/null | head -n1 || true)"
    if [ -n "${B:-}" ] && [ -f "$B" ]; then
      cp -f "$B" "$F"
      echo "[RESTORE] $F <= $B"
    fi
  fi
}
restore_if_stub "static/js/vsp_tabs_hash_router_v1.js"

# (1) Build ordered candidate list -> out_ci/bundle_v2_files.list
python3 - <<'PY'
from pathlib import Path

jsdir = Path("static/js")
tpl = Path("out_ci/bundle_v2_files.list")

def is_backup(p: Path) -> bool:
  n = p.name
  return (".bak_" in n) or n.endswith(".bak") or n.endswith(".tmp")

allf = sorted([p for p in jsdir.glob("vsp_*.js") if p.is_file()])
cands = []
for p in allf:
  n = p.name
  if is_backup(p): 
    continue
  if n.startswith("vsp_bundle_commercial_"):
    continue
  if n == "vsp_ui_loader_route_v1.js":
    continue
  cands.append(p)

picked = []
used = set()

# exact first
for name in ["vsp_tabs_hash_router_v1.js"]:
  for p in cands:
    if p.name == name and p.name not in used:
      picked.append(p); used.add(p.name)

def pick_contains(substr):
  for p in cands:
    if p.name in used:
      continue
    if substr in p.name:
      picked.append(p); used.add(p.name)

# prefer key modules next (best-effort)
for key in [
  "vsp_dashboard_enhance", "vsp_dashboard_charts", "vsp_degraded",
  "vsp_runs", "vsp_settings", "vsp_rule_overrides", "vsp_data", "vsp_ui"
]:
  pick_contains(key)

# rest
for p in cands:
  if p.name not in used:
    picked.append(p); used.add(p.name)

tpl.write_text("\n".join([str(p) for p in picked]) + "\n", encoding="utf-8")
print("[OK] wrote", tpl.as_posix(), "count=", len(picked))
PY

echo "== candidates (ordered) =="
nl -ba out_ci/bundle_v2_files.list | head -n 120

# (2) Filter by syntax -> ok/bad lists
: > out_ci/bundle_v2_files_ok.list
: > out_ci/bundle_v2_files_bad.list
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if node --check "$f" >/dev/null 2>&1; then
    echo "$f" >> out_ci/bundle_v2_files_ok.list
  else
    echo "$f" >> out_ci/bundle_v2_files_bad.list
  fi
done < out_ci/bundle_v2_files.list

echo "== syntax OK files =="
wc -l out_ci/bundle_v2_files_ok.list | awk '{print "[OK_COUNT]",$1}'
echo "== syntax BAD files (excluded) =="
if [ -s out_ci/bundle_v2_files_bad.list ]; then
  nl -ba out_ci/bundle_v2_files_bad.list | head -n 200
else
  echo "(none)"
fi

# (3) Write bundle v2
python3 - <<'PY'
from pathlib import Path
import datetime

out = Path("static/js/vsp_bundle_commercial_v2.js")
files = [Path(x.strip()) for x in Path("out_ci/bundle_v2_files_ok.list").read_text(encoding="utf-8").splitlines() if x.strip()]
ts = datetime.datetime.now().isoformat()

prologue = r'''
/* VSP_BUNDLE_COMMERCIAL_V2 (rebuilt) */
(function(){
  'use strict';
  try{ window.__VSP_BUNDLE_COMMERCIAL_V2 = true; }catch(_){}
  // safe drilldown + legacy symbols
  if (typeof window.VSP_DRILLDOWN !== "function") {
    window.VSP_DRILLDOWN = function(intent){
      try{
        try{ localStorage.setItem("vsp_last_drilldown_intent_v1", JSON.stringify(intent||{})); }catch(_){}
        try{ if (location && typeof location.hash==="string" && !location.hash.includes("datasource")) location.hash="#datasource"; }catch(_){}
        return true;
      }catch(e){ return false; }
    };
  }
  try{
    var dd = function(intent){ return window.VSP_DRILLDOWN(intent); };
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = dd;
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 = dd;
    window.VSP_DASH_DRILLDOWN_ARTIFACTS = dd;
  }catch(_){}
})();
'''

buf = [prologue, f"\n/* build_ts: {ts} */\n\n"]
for p in files:
  s = p.read_text(encoding="utf-8", errors="replace")
  buf.append(f"\n/* ==== BEGIN: {p.as_posix()} ==== */\n")
  buf.append("(function(){\n'use strict';\n")
  buf.append(s)
  buf.append("\n})();\n")
  buf.append(f"/* ==== END: {p.as_posix()} ==== */\n")

out.write_text("".join(buf), encoding="utf-8")
print("[OK] wrote", out.as_posix(), "bytes=", out.stat().st_size, "files=", len(files))
PY

echo "== node --check bundle v2 =="
node --check "$OUT" && echo "[OK] bundle v2 syntax OK"

# (4) Patch top-level templates -> load ONLY bundle v2
python3 - <<'PY'
from pathlib import Path
import re, datetime

tpl_dir = Path("templates")
if not tpl_dir.exists():
  print("[WARN] templates/ not found")
  raise SystemExit(0)

TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bundle_tag = '<script defer src="/static/js/vsp_bundle_commercial_v2.js?v={{ asset_v }}"></script>'

script_re = re.compile(r'(?is)\s*<script\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\'][^>]*>\s*</script\s*>\s*')

def is_top(txt: str) -> bool:
  low = txt.lower()
  return ("<html" in low) and ("</body" in low)

patched = 0
for tp in sorted(tpl_dir.rglob("*.html")):
  txt = tp.read_text(encoding="utf-8", errors="replace")
  if not is_top(txt):
    continue

  removed = 0
  def repl(m):
    nonlocal removed
    src = (m.group(1) or "").strip()
    if "/static/js/vsp_" in src or "static/js/vsp_" in src:
      removed += 1
      return "\n"
    return m.group(0)

  new = script_re.sub(repl, txt)
  new = re.sub(r'(?is)\s*<script\b[^>]*vsp_bundle_commercial_v2\.js[^>]*>\s*</script\s*>\s*', "\n", new)
  if re.search(r"(?is)</body\s*>", new):
    new = re.sub(r"(?is)</body\s*>", "\n" + bundle_tag + "\n</body>", new, count=1)
  else:
    new += "\n" + bundle_tag + "\n"

  if new != txt:
    bak = tp.with_suffix(tp.suffix + f".bak_bundlev2_{TS}")
    bak.write_text(txt, encoding="utf-8")
    tp.write_text(new, encoding="utf-8")
    print(f"[OK] patched {tp.as_posix()} removed_scripts={removed}")
    patched += 1

print("[DONE] templates_patched=", patched)
PY

echo "== DONE =="
echo "[NEXT] restart 8910 + HARD refresh Ctrl+Shift+R"
echo "[NOTE] excluded files: out_ci/bundle_v2_files_bad.list"
