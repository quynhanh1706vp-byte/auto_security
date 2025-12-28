#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need awk; need head; need sort

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR] $*"; exit 2; }

tmp="$(mktemp -d /tmp/vsp_ui_smoke_nobrowser_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
ok "tmp=$tmp"

pages=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== [1] Fetch pages =="
for p in "${pages[@]}"; do
  name="$(echo "$p" | tr '/' '_')"   # /vsp5 -> _vsp5
  curl -fsS "$BASE$p" -o "$tmp/${name}.html"
done
ok "pages saved"

echo
echo "== DEBUG ls tmp =="
ls -lah "$tmp" | sed -n '1,40p'

echo
echo "== [2] Template leak markers in HTML ({{ or {%}) =="
if grep -R -nE '\{\{|\{\%' "$tmp"/*.html >/dev/null 2>&1; then
  warn "template markers found:"
  grep -R -nE '\{\{|\{\%' "$tmp"/*.html | head -n 50
else
  ok "no template leak markers"
fi

echo
echo "== [3] Extract assets + HEAD check =="
assets="$(cat "$tmp"/*.html | grep -oE 'static/(js|css)/[^"'\'' ]+' | sed 's/[?].*$//' | sort -u || true)"
if [ -z "$assets" ]; then
  warn "no assets found in HTML (unexpected)"
else
  cnt=0; bad=0
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    code="$(curl -s -o /dev/null -w "%{http_code}" -I "$BASE/$a" || true)"
    cnt=$((cnt+1))
    if [ "$code" != "200" ]; then
      bad=$((bad+1))
      warn "$a => $code"
    fi
  done <<< "$assets"
  if [ "$bad" -eq 0 ]; then ok "assets HEAD 200: $cnt files"; else warn "assets bad=$bad/$cnt"; fi
fi

echo
echo "== [4] Quick error signatures in HTML =="
sig='Uncaught|ReferenceError|TypeError|Failed to load|stack trace'
if grep -R -nE "$sig" "$tmp"/*.html >/dev/null 2>&1; then
  warn "found suspicious patterns:"
  grep -R -nE "$sig" "$tmp"/*.html | head -n 80
else
  ok "no obvious error patterns in HTML"
fi

echo
echo "== [5] KPI/Charts contract =="
kpis="$(curl -fsS "$BASE/api/vsp/dash_kpis" | head -c 800)"
charts="$(curl -fsS "$BASE/api/vsp/dash_charts" | head -c 800)"
echo "dash_kpis: $kpis"
echo "dash_charts: $charts"

echo
ok "smoke finished"
