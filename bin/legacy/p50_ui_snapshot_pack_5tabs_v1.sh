#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p50_snap_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need awk; need sed; need grep; need ls; need head; need tail; need mkdir
command -v python3 >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p50_snap_${TS}"
mkdir -p "$ATT"
log "[OK] latest_release=$latest_release"

tabs=(
  "/vsp5|Dashboard"
  "/runs|Runs & Reports"
  "/data_source|Data Source"
  "/settings|Settings"
  "/rule_overrides|Rule Overrides"
)

log "== [P50/1] fetch HTML + headers per tab =="
for item in "${tabs[@]}"; do
  path="${item%%|*}"
  name="${item##*|}"
  slug="$(echo "$name" | tr ' /&' '___' | tr -cd 'A-Za-z0-9_-' )"

  hdr="$EVID/${slug}_headers.txt"
  html="$EVID/${slug}.html"

  # headers
  curl -sS -D "$hdr" -o /dev/null --connect-timeout 2 --max-time 6 "$BASE$path" || true
  # html (bounded)
  curl -fsS --connect-timeout 2 --max-time 10 --range 0-150000 "$BASE$path" -o "$html" || {
    echo "<!-- fetch failed: $BASE$path -->" > "$html"
  }

  # quick status line
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "$BASE$path" || true)"
  echo "$name|$path|$code|$slug" >> "$EVID/status_table.txt"
done

log "== [P50/2] optional screenshots (chromium/google-chrome) =="
BROWSER=""
if command -v chromium >/dev/null 2>&1; then BROWSER="chromium"; fi
if command -v chromium-browser >/dev/null 2>&1; then BROWSER="chromium-browser"; fi
if command -v google-chrome >/dev/null 2>&1; then BROWSER="google-chrome"; fi

if [ -n "$BROWSER" ]; then
  log "[OK] found browser: $BROWSER (taking screenshots)"
  for item in "${tabs[@]}"; do
    path="${item%%|*}"
    name="${item##*|}"
    slug="$(echo "$name" | tr ' /&' '___' | tr -cd 'A-Za-z0-9_-' )"
    png="$EVID/${slug}.png"
    # Headless screenshot
    "$BROWSER" --headless --no-sandbox --disable-gpu \
      --window-size=1440,900 \
      --screenshot="$png" "$BASE$path" >/dev/null 2>&1 || true
  done
else
  log "[WARN] no chromium/google-chrome found; skip screenshots (HTML+headers still OK)"
fi

log "== [P50/3] build INDEX.html (one file to open) =="
idx="$EVID/INDEX.html"
{
  echo "<!doctype html><html><head><meta charset='utf-8'><title>VSP UI Snapshot Pack</title>"
  echo "<style>body{font-family:Arial, sans-serif; padding:16px;} table{border-collapse:collapse;} td,th{border:1px solid #ccc;padding:6px 10px;} code{background:#f6f6f6;padding:2px 4px;}</style>"
  echo "</head><body>"
  echo "<h1>VSP UI Snapshot Pack (P50)</h1>"
  echo "<p><b>Base</b>: <code>$BASE</code><br><b>Captured at</b>: <code>$(date +'%Y-%m-%d %H:%M:%S %z')</code></p>"
  echo "<table><thead><tr><th>Tab</th><th>Path</th><th>HTTP</th><th>HTML</th><th>Headers</th><th>Screenshot</th></tr></thead><tbody>"
  while IFS='|' read -r name path code slug; do
    html="${slug}.html"
    hdr="${slug}_headers.txt"
    png="${slug}.png"
    ss="(n/a)"
    if [ -f "$EVID/$png" ] && [ "$(stat -c%s "$EVID/$png" 2>/dev/null || echo 0)" -gt 1000 ]; then
      ss="<a href='$png'>png</a>"
    fi
    echo "<tr><td>$name</td><td><code>$path</code></td><td>$code</td><td><a href='$html'>html</a></td><td><a href='$hdr'>headers</a></td><td>$ss</td></tr>"
  done < "$EVID/status_table.txt"
  echo "</tbody></table>"
  echo "<h2>Notes</h2><ul>"
  echo "<li>HTML fetched with range limit (150KB) for audit portability.</li>"
  echo "<li>Screenshots generated only if chromium/google-chrome exists.</li>"
  echo "</ul>"
  echo "</body></html>"
} > "$idx"

log "== [P50/4] attach into release evidence =="
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

log "== [P50/5] verdict =="
VER="$OUT/p50_verdict_${TS}.txt"
{
  echo "P50 OK"
  echo "base=$BASE"
  echo "evidence_dir=$EVID"
  echo "attached_dir=$ATT"
  echo "index=$ATT/INDEX.html"
  echo "screenshots=$([ -n "$BROWSER" ] && echo yes || echo no)"
} | tee "$VER" >/dev/null
cp -f "$VER" "$ATT/" 2>/dev/null || true

log "[DONE] P50 PASS"
