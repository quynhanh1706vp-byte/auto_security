#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56h2b_ui_audit_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need grep; need sed; need awk; need python3; need node

CHROME="$(command -v google-chrome || command -v chromium || command -v chromium-browser || true)"

tabs=(
  "vsp5:/vsp5"
  "runs:/runs"
  "data_source:/data_source"
  "settings:/settings"
  "rule_overrides:/rule_overrides"
)

echo "== [P56H2b] HEADLESS UI AUDIT (no Playwright) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"
echo "[INFO] CHROME=${CHROME:-NONE}" | tee -a "$EVID/summary.txt"

# 1) HTTP reachability with retry (so /vsp5 cold start won't false-fail)
probe_one(){
  local path="$1"
  local code="000"
  for i in 1 2 3 4 5 6; do
    code="$(curl -fsS --connect-timeout 2 --max-time 10 -o /dev/null -w '%{http_code}' "$BASE$path" || echo 000)"
    echo "[HTTP] try#$i $path => $code" >> "$EVID/http_tries.txt"
    if [[ "$code" =~ ^2|^3 ]]; then break; fi
    sleep 1
  done
  echo "$code"
}

ok_http=1
> "$EVID/http_codes.txt"
for t in "${tabs[@]}"; do
  name="${t%%:*}"; path="${t#*:}"
  code="$(probe_one "$path")"
  printf "%-14s %s %s\n" "$name" "$path" "$code" | tee -a "$EVID/http_codes.txt" >> "$EVID/summary.txt"
  if [[ ! "$code" =~ ^2|^3 ]]; then ok_http=0; fi
done

# 2) Dump DOM + screenshot by headless chrome (no UI open)
> "$EVID/dom_nav_check.txt"
if [ -n "$CHROME" ]; then
  for t in "${tabs[@]}"; do
    name="${t%%:*}"; path="${t#*:}"
    url="$BASE$path"

    # dump dom (let JS run a bit)
    "$CHROME" --headless=new --disable-gpu --no-sandbox --window-size=1440,900 \
      --virtual-time-budget=12000 --dump-dom "$url" > "$EVID/${name}.html" 2> "$EVID/${name}.chrome_stderr.txt" || true

    # screenshot
    "$CHROME" --headless=new --disable-gpu --no-sandbox --window-size=1440,900 \
      --virtual-time-budget=12000 --screenshot="$EVID/${name}.png" "$url" >/dev/null 2>&1 || true

    # basic nav text check (avoid "blank dark screen")
    if grep -Eq 'Dashboard|Runs\s*&\s*Reports|Data\s*Source|Settings|Rule\s*Overrides' "$EVID/${name}.html" 2>/dev/null; then
      echo "[NAV] $name OK" >> "$EVID/dom_nav_check.txt"
    else
      echo "[NAV] $name MISSING" >> "$EVID/dom_nav_check.txt"
    fi
  done
else
  echo "[WARN] no chrome found -> only curl html fallback" | tee -a "$EVID/summary.txt"
  for t in "${tabs[@]}"; do
    name="${t%%:*}"; path="${t#*:}"
    curl -fsS --connect-timeout 2 --max-time 10 "$BASE$path" -o "$EVID/${name}.html" || true
    if grep -Eq 'Dashboard|Runs\s*&\s*Reports|Data\s*Source|Settings|Rule\s*Overrides' "$EVID/${name}.html" 2>/dev/null; then
      echo "[NAV] $name OK" >> "$EVID/dom_nav_check.txt"
    else
      echo "[NAV] $name MISSING" >> "$EVID/dom_nav_check.txt"
    fi
  done
fi

# 3) Extract LOADED JS from dumped DOM (5 tabs)
> "$EVID/loaded_js.txt"
for t in "${tabs[@]}"; do
  name="${t%%:*}"
  grep -oE '/static/js/[^"]+\.js(\?[^"]*)?' "$EVID/${name}.html" 2>/dev/null \
    | sed -E 's/\?.*$//' >> "$EVID/loaded_js.txt" || true
done
sort -u "$EVID/loaded_js.txt" -o "$EVID/loaded_js.txt"
echo "[OK] loaded_js_count=$(wc -l < "$EVID/loaded_js.txt")" | tee -a "$EVID/summary.txt"

# 4) Syntax check only LOADED JS (important: not all 200+ files)
bad=0
> "$EVID/loaded_js_syntax_fail.txt"
while IFS= read -r url; do
  [ -n "$url" ] || continue
  f="${url#/}"
  if [ -f "$f" ]; then
    if ! node --check "$f" >/dev/null 2>&1; then
      echo "$f" >> "$EVID/loaded_js_syntax_fail.txt"
      bad=1
    fi
  fi
done < "$EVID/loaded_js.txt"
echo "[OK] loaded_js_syntax_fail_count=$(wc -l < "$EVID/loaded_js_syntax_fail.txt")" | tee -a "$EVID/summary.txt"

# 5) Scan obvious error markers in DOM (DEGRADED / Failed / SyntaxError strings)
> "$EVID/dom_error_markers.txt"
for t in "${tabs[@]}"; do
  name="${t%%:*}"
  grep -nEi 'Uncaught|SyntaxError|ReferenceError|TypeError|Failed to load|DEGRADED|dashboard data not ready|runs API failed' \
    "$EVID/${name}.html" 2>/dev/null | head -n 40 | sed "s/^/${name}:/" >> "$EVID/dom_error_markers.txt" || true
done
markers_count="$(wc -l < "$EVID/dom_error_markers.txt")"
echo "[OK] dom_error_markers_count=$markers_count" | tee -a "$EVID/summary.txt"

# 6) Verdict (always create verdict.json)
python3 - <<PY
import json, pathlib
evid = pathlib.Path("$EVID")
ok_http = bool(int("$ok_http"))
nav = (evid/"dom_nav_check.txt").read_text(errors="ignore") if (evid/"dom_nav_check.txt").exists() else ""
nav_missing = [line for line in nav.splitlines() if "MISSING" in line]
syntax_fail = (evid/"loaded_js_syntax_fail.txt").read_text(errors="ignore").strip().splitlines() if (evid/"loaded_js_syntax_fail.txt").exists() else []
markers = (evid/"dom_error_markers.txt").read_text(errors="ignore").strip().splitlines() if (evid/"dom_error_markers.txt").exists() else []

verdict = {
  "ok": ok_http and (len(nav_missing)==0) and (len(syntax_fail)==0) and (len(markers)==0),
  "base": "$BASE",
  "ts": "$TS",
  "evidence_dir": "$EVID",
  "checks": {
    "http_all_tabs_ok": ok_http,
    "nav_missing": nav_missing,
    "loaded_js_syntax_fail": syntax_fail[:200],
    "dom_error_markers_top": markers[:200],
  }
}
(evid/"verdict.json").write_text(json.dumps(verdict, indent=2, ensure_ascii=False))
print(json.dumps(verdict, indent=2, ensure_ascii=False))
PY

echo "[DONE] evidence=$EVID" | tee -a "$EVID/summary.txt"
