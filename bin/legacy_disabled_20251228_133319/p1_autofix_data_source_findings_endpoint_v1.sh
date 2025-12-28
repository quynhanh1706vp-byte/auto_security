#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-RUN_20251120_130310}"
JS="static/js/vsp_data_source_tab_v3.js"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need grep; need sed

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
TMP="$(mktemp -d /tmp/vsp_findings_probe.XXXXXX)"
HDR="$TMP/hdr.txt"
BODY="$TMP/body.txt"

echo "[BASE] $BASE"
echo "[RID ] $RID"
echo "[JS  ] $JS"
echo "[TMP ] $TMP"

probe(){
  local path="$1"
  : > "$HDR"; : > "$BODY"
  local code
  code="$(curl -sS -D "$HDR" -o "$BODY" -w "%{http_code}" \
    "$BASE${path}?rid=${RID}&limit=1&offset=0" || true)"
  local sz
  sz="$(wc -c < "$BODY" | tr -d ' ')"
  echo "== PROBE $path => HTTP $code body_bytes=$sz =="
  head -n 2 "$HDR" | sed 's/\r$//'
  head -c 200 "$BODY"; echo
  # accept if 200 + looks like JSON with ok:true/false
  if [ "$code" = "200" ] && grep -qE '^\s*\{' "$BODY" && grep -q '"ok"' "$BODY"; then
    echo "$path"
    return 0
  fi
  return 1
}

FOUND=""
for ep in /api/ui/findings_v3 /api/ui/findings_v2 /api/ui/findings_v1 /api/ui/findings_safe_v1; do
  if FOUND="$(probe "$ep")"; then
    break
  fi
done

if [ -z "$FOUND" ]; then
  echo "[ERR] No working findings endpoint found. Check server logs: out_ci/ui_8910.error.log"
  exit 2
fi

echo "[OK] working findings endpoint = $FOUND"

# patch JS to use FOUND (replace any /api/ui/findings_* to FOUND)
cp -f "$JS" "${JS}.bak_findings_ep_${TS}"
python3 - "$JS" "$FOUND" <<'PY'
import re, sys, pathlib
js = pathlib.Path(sys.argv[1])
found = sys.argv[2]
s = js.read_text(encoding="utf-8", errors="replace")
s2, n = re.subn(r'"/api/ui/findings_[^"]*', f'"{found}', s)
if n == 0:
    # fallback: single quotes
    s2, n = re.subn(r"'/api/ui/findings_[^']*", f"'{found}", s)
js.write_text(s2, encoding="utf-8")
print("[OK] patched JS replacements=", n)
PY

echo "[DONE] Patched $JS. Now hard-refresh /data_source (Ctrl+Shift+R)."
echo "[HINT] Quick verify:"
echo "  curl -sS \"$BASE${FOUND}?rid=$RID&limit=1&offset=0\" | head -c 400; echo"
