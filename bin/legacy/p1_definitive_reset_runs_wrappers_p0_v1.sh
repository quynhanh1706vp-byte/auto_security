#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# target files that got polluted
TEMPLATES=(
  templates/vsp_5tabs_enterprise_v2.html
  templates/vsp_dashboard_2025.html
  templates/vsp_runs_reports_v1.html
  templates/vsp_rule_overrides_v1.html
  templates/vsp_settings_v1.html
  templates/vsp_data_source_2025.html
  templates/vsp_data_source_v1.html
)
JSFILES=(
  static/js/vsp_bundle_commercial_v2.js
  static/js/vsp_bundle_commercial_v1.js
  static/js/vsp_runs_tab_resolved_v1.js
  static/js/vsp_app_entry_safe_v1.js
  static/js/vsp_fill_real_data_5tabs_p1_v1.js
)

python3 - <<'PY'
from pathlib import Path
import re, time, shutil, os

TS = time.strftime("%Y%m%d_%H%M%S")

BAD_MARKERS = [
  "VSP_P0_RUNS", "VSP_RUNS_", "RUNS_FETCH", "runs fetch", "runs FAIL",
  "cache+fallback for /api/vsp/runs", "force ok:true for /api/vsp/runs",
  "HARD bypass", "DOM-killer", "RUNS API FAIL", "NETGUARD_GLOBAL",
  "VSP_P1_NETGUARD_GLOBAL", "VSP_P0_RUNS_FETCH_LOCK",
  "stable fetch shim enabled", "fetch shim enabled",
]

def is_clean(text: str) -> bool:
  t = text
  return not any(m.lower() in t.lower() for m in BAD_MARKERS)

def pick_clean_backup(p: Path):
  # newest -> oldest, pick first that looks clean
  baks = sorted(p.parent.glob(p.name + ".bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)
  for b in baks:
    try:
      s = b.read_text(encoding="utf-8", errors="replace")
    except Exception:
      continue
    if is_clean(s):
      return b
  return None

def hard_strip_html(s: str) -> str:
  # remove injected blocks with VSP_P0/VSP_P1 ids (typical injection)
  s2 = s
  s2 = re.sub(r'(?is)\s*<!--\s*VSP_[^-]*?\s*-->\s*', '\n', s2)

  # remove <script id="VSP_P0...">...</script> and <script id="VSP_P1...">...</script>
  s2 = re.sub(r'(?is)\s*<script[^>]*\bid\s*=\s*"(VSP_(P0|P1)[^"]*)"[^>]*>.*?</script>\s*', '\n', s2)

  # remove any script blocks containing the bad markers (even without id)
  for m in BAD_MARKERS:
    s2 = re.sub(r'(?is)\s*<script[^>]*>[^<]*?' + re.escape(m) + r'.*?</script>\s*', '\n', s2)

  # de-dupe excessive blank lines
  s2 = re.sub(r'\n{3,}', '\n\n', s2)
  return s2

def backup(p: Path):
  if not p.exists():
    return None
  dst = p.with_name(p.name + f".bak_runs_reset_{TS}")
  shutil.copy2(p, dst)
  return dst

changed = []

# 1) templates: try restore clean backup, else strip injected scripts
tpls = [
  Path("templates/vsp_5tabs_enterprise_v2.html"),
  Path("templates/vsp_dashboard_2025.html"),
  Path("templates/vsp_runs_reports_v1.html"),
  Path("templates/vsp_rule_overrides_v1.html"),
  Path("templates/vsp_settings_v1.html"),
  Path("templates/vsp_data_source_2025.html"),
  Path("templates/vsp_data_source_v1.html"),
]
for p in tpls:
  if not p.exists():
    print("[SKIP] missing:", p)
    continue
  backup(p)
  b = pick_clean_backup(p)
  if b:
    shutil.copy2(b, p)
    changed.append(str(p))
    print(f"[RESTORE] {p} <= {b.name}")
  else:
    s = p.read_text(encoding="utf-8", errors="replace")
    s2 = hard_strip_html(s)
    if s2 != s:
      p.write_text(s2, encoding="utf-8")
      changed.append(str(p))
      print(f"[STRIP] {p} stripped injected blocks")
    else:
      print(f"[OK] {p} no injected blocks found")

# 2) JS: restore clean backup if exists; otherwise leave but we’ll still try to remove obvious injected tails
js = [
  Path("static/js/vsp_bundle_commercial_v2.js"),
  Path("static/js/vsp_bundle_commercial_v1.js"),
  Path("static/js/vsp_runs_tab_resolved_v1.js"),
  Path("static/js/vsp_app_entry_safe_v1.js"),
  Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js"),
]
def hard_strip_js(s: str) -> str:
  s2 = s
  # remove common injected “marker blocks” by marker header lines
  # We cut from a marker line to the next marker line or EOF (conservative).
  pat = r'(?is)(?:^|\n)[^\n]*(VSP_P0_RUNS|VSP_RUNS_|NETGUARD_GLOBAL|RUNS_FETCH|HARD bypass|DOM-killer)[^\n]*\n'
  while True:
    m = re.search(pat, s2)
    if not m: break
    start = m.start()
    # find next marker occurrence after this one
    m2 = re.search(pat, s2[m.end():])
    end = (m.end() + m2.start()) if m2 else len(s2)
    s2 = s2[:start] + "\n/* [REMOVED injected RUNS wrapper block] */\n" + s2[end:]
  return s2

for p in js:
  if not p.exists():
    print("[SKIP] missing:", p)
    continue
  backup(p)
  b = pick_clean_backup(p)
  if b:
    shutil.copy2(b, p)
    changed.append(str(p))
    print(f"[RESTORE] {p} <= {b.name}")
  else:
    s = p.read_text(encoding="utf-8", errors="replace")
    s2 = hard_strip_js(s)
    if s2 != s:
      p.write_text(s2, encoding="utf-8")
      changed.append(str(p))
      print(f"[STRIP] {p} removed injected marker blocks")
    else:
      print(f"[OK] {p} no marker blocks found")

print("[DONE] changed files =", len(changed))
for x in changed:
  print(" -", x)
PY

# quick syntax checks
for f in static/js/vsp_bundle_commercial_v2.js static/js/vsp_bundle_commercial_v1.js static/js/vsp_runs_tab_resolved_v1.js static/js/vsp_app_entry_safe_v1.js static/js/vsp_fill_real_data_5tabs_p1_v1.js; do
  [ -f "$f" ] || continue
  node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check $f" || echo "[WARN] node --check FAILED $f"
done

echo "[NEXT] Restart UI and HARD refresh (Ctrl+F5) /runs and /vsp5."
echo "       Also: open Incognito once to avoid stale cached JS/localStorage."
