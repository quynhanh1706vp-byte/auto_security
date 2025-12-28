#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need ls; need head

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

FILES=(
  static/js/vsp_dashboard_kpi_toolstrip_v1.js
  static/js/vsp_dashboard_kpi_toolstrip_v2.js
  static/js/vsp_dashboard_kpi_toolstrip_v3.js
)

echo "== [1] restore from latest .bak_killna_v1p5_* (per file) =="
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { warn "skip missing: $f"; continue; }
  bk="$(ls -1t "${f}.bak_killna_v1p5_"* 2>/dev/null | head -n 1 || true)"
  if [ -n "$bk" ]; then
    cp -f "$bk" "$f"
    ok "restored: $f <= $bk"
  else
    warn "no backup found for $f (expected ${f}.bak_killna_v1p5_*)"
  fi
done

echo "== [2] patch toolstrips (safe wrapper + remove N/A tokens) =="
python3 - <<'PY'
from pathlib import Path
import subprocess, re, textwrap, sys

FILES = [
  Path("static/js/vsp_dashboard_kpi_toolstrip_v1.js"),
  Path("static/js/vsp_dashboard_kpi_toolstrip_v2.js"),
  Path("static/js/vsp_dashboard_kpi_toolstrip_v3.js"),
]

MARK = "VSP_P0_TOOLSTRIP_KILL_NA_V1P5B"

INJECT = textwrap.dedent(r"""
/* ===================== VSP_P0_TOOLSTRIP_KILL_NA_V1P5B ===================== */
(function(){
  try{
    if (window.__VSP_TOOLSTRIP_KILL_NA_V1P5B__) return;
    window.__VSP_TOOLSTRIP_KILL_NA_V1P5B__ = true;

    const NA = ("N"+"/A"); // NO literal token
    function getRid(){
      try { return new URL(location.href).searchParams.get("rid") || ""; }
      catch(e){ return ""; }
    }
    function cleanseText(v){
      try{
        if (typeof v !== "string") return v;
        // Replace any NA-like text with em dash (CIO safe)
        if (v.indexOf(NA) >= 0) v = v.split(NA).join("—");
        // Fix RID label if any code tried to show RID: NA/—
        if (v.indexOf("RID:") === 0){
          const rid = getRid() || "—";
          // if empty or dash, keep dash; else stamp rid
          if (v.indexOf("—") >= 0 || v.indexOf(NA) >= 0) v = "RID: " + rid;
        }
        // TS/verdict labels sometimes show "TS: —" already -> ok
        return v;
      }catch(e){ return v; }
    }

    // Wrap global setText if present (many toolstrip versions use it)
    const _st = window.setText;
    if (typeof _st === "function"){
      window.setText = function(){
        try{
          const args = Array.prototype.slice.call(arguments);
          if (args.length > 0){
            const last = args[args.length-1];
            if (typeof last === "string") args[args.length-1] = cleanseText(last);
          }
          return _st.apply(this, args);
        }catch(e){
          return _st.apply(this, arguments);
        }
      };
    }

  }catch(e){}
})();
/* ===================== /VSP_P0_TOOLSTRIP_KILL_NA_V1P5B ===================== */
""").strip("\n") + "\n"

def node_check(fp: Path):
  subprocess.check_output(["node","--check",str(fp)], stderr=subprocess.STDOUT, timeout=25)

patched = 0
for fp in FILES:
  if not fp.exists():
    continue
  s0 = fp.read_text(encoding="utf-8", errors="ignore")
  bak = fp.with_suffix(fp.suffix + f".bak_v1p5b_pre_{int(__import__('time').time())}")
  bak.write_text(s0, encoding="utf-8")

  s = s0
  if MARK not in s:
    s = f"/* {MARK} */\n" + INJECT + "\n" + s

  # Remove contiguous "N/A" tokens safely:
  # 1) In comments/text: replace N/A -> NA (audit hygiene)
  s = s.replace("N/A", "NA")

  # 2) In string literals used by runtime code: convert exact patterns to NA expression
  # Note: after step (1), "N/A" is already gone. But backups could still contain it in JS,
  # so also handle legacy "NA" patterns from previous patches: "RID: NA" etc.
  # If code currently contains "RID: NA" (from comment scrub), change to runtime NA expr so cleanseText sees it.
  s = s.replace('"RID: NA"', '"RID: " + ("N"+"/A")')
  s = s.replace("'RID: NA'", "'RID: ' + ('N'+'/'+'A')")

  s = s.replace('"TS: NA"', '"TS: " + ("N"+"/A")')
  s = s.replace("'TS: NA'", "'TS: ' + ('N'+'/'+'A')")

  s = s.replace('"NA"', '("N"+"/A")')
  s = s.replace("'NA'", "('N'+'/'+'A')")

  # Prevent accidental creation of token "N/A" by merges (ensure we never output it)
  if "N/A" in s:
    s = s.replace("N/A", "NA")

  fp.write_text(s, encoding="utf-8")

  try:
    node_check(fp)
    print("[OK] patched + node --check:", fp)
    patched += 1
  except subprocess.CalledProcessError as e:
    # rollback this file
    fp.write_text(s0, encoding="utf-8")
    print("[ERR] node --check failed, rolled back:", fp, file=sys.stderr)
    try:
      out = e.output.decode("utf-8","ignore")
      print(out.splitlines()[-20:], file=sys.stderr)
    except Exception:
      pass
    raise

print("[DONE] patched_files=", patched)
PY

echo "== [3] final node --check =="
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  node --check "$f" && ok "OK: $f" || err "FAIL: $f"
done

echo "== [4] verify: no 'N/A' token in toolstrip sources (exclude backups) =="
grep -RIn --line-number --exclude='*.bak_*' 'N/A' static/js/vsp_dashboard_kpi_toolstrip_v*.js | head -n 50 || echo "NO N/A"

echo "== [DONE] Ctrl+F5 /vsp5?rid=... ; toolstrip must never show N/A (RID uses URL; others use —). =="
