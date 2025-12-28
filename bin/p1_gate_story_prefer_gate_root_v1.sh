#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
FILES=(
  "static/js/vsp_dashboard_gate_story_v1.js"
  "static/js/vsp_bundle_commercial_v2.js"
)

python3 - <<'PY'
from pathlib import Path
import re, time

files = [
  Path("static/js/vsp_dashboard_gate_story_v1.js"),
  Path("static/js/vsp_bundle_commercial_v2.js"),
]

def patch_one(p: Path) -> int:
  if not p.exists():
    print(f"[WARN] missing {p}")
    return 0

  s = p.read_text(encoding="utf-8", errors="replace")
  if "VSP_P1_PREFER_GATE_ROOT_V1" in s:
    print(f"[SKIP] already patched: {p}")
    return 1

  # backup
  ts = time.strftime("%Y%m%d_%H%M%S")
  bak = p.with_name(p.name + f".bak_prefer_gate_root_{ts}")
  bak.write_text(s, encoding="utf-8")
  print(f"[BACKUP] {bak}")

  # We inject a tiny block right AFTER reading JSON from /api/vsp/runs:
  # - If rid_latest_gate_root exists: force rid_last_good and rid_latest to that gate_root.
  # This makes any existing "pick last_good" logic automatically pick gate_root.
  inject_tmpl = r"""
/* VSP_P1_PREFER_GATE_ROOT_V1 */
try{
  if (%(J)s && %(J)s.rid_latest_gate_root){
    %(J)s.__vsp_prefer_gate_root = true;
    %(J)s.__vsp_gate_root = %(J)s.rid_latest_gate_root;
    // Force pickers that prefer last_good/latest to land on CI gate_root
    %(J)s.rid_last_good = %(J)s.rid_latest_gate_root;
    %(J)s.rid_latest = %(J)s.rid_latest_gate_root;
    console.log("[VSP][GateStory] prefer gate_root:", %(J)s.rid_latest_gate_root);
  }
}catch(e){
  console.warn("[VSP][GateStory] prefer gate_root inject err", e);
}
"""

  n = 0
  s2 = s

  # Pattern A: async/await JSON read:  const j = await res.json();
  pat_await = re.compile(r'(\b(?:const|let|var)\s+(\w+)\s*=\s*await\s+\w+\.json\(\)\s*;\s*)')
  def repl_await(m):
    nonlocal n
    full = m.group(1)
    jvar = m.group(2)
    n += 1
    return full + inject_tmpl % {"J": jvar}

  s2, c1 = pat_await.subn(repl_await, s2, count=1)
  if c1:
    print(f"[OK] patched (await-json) in {p}")
  else:
    # Pattern B: then-chain JSON read: .then(j => { ... })
    # We look for: .then(<jvar> => {   and inject right after the opening brace IF this then is reached from /api/vsp/runs block.
    # To keep it safe, first ensure file references '/api/vsp/runs'
    if "/api/vsp/runs" not in s2:
      print(f"[WARN] no /api/vsp/runs in {p} => skip")
      return 0

    # Find the first ".then(" callback with a single param and "{" body
    pat_then = re.compile(r'(\.then\(\s*(\w+)\s*=>\s*\{\s*)')
    def repl_then(m):
      nonlocal n
      head = m.group(1)
      jvar = m.group(2)
      n += 1
      return head + (inject_tmpl % {"J": jvar})
    s2, c2 = pat_then.subn(repl_then, s2, count=1)
    if c2:
      print(f"[OK] patched (then-callback) in {p}")
    else:
      print(f"[WARN] could not find patch point in {p}")
      return 0

  p.write_text(s2, encoding="utf-8")
  return 1

patched = 0
for f in files:
  patched += patch_one(f)

if patched == 0:
  raise SystemExit("[ERR] patched=0 (no file changed) — please paste the /api/vsp/runs fetch snippet for exact patch.")
print(f"[DONE] patched_files={patched}")
PY

echo "== node --check =="
node --check static/js/vsp_dashboard_gate_story_v1.js
node --check static/js/vsp_bundle_commercial_v2.js
echo "[OK] syntax OK"

echo "== quick smoke curl =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -sS -I "$BASE/vsp5" | sed -n '1,12p'
echo "[OK] open $BASE/vsp5 and check console: should log prefer gate_root"
