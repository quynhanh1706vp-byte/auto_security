#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need curl; need grep; need awk; need sed; need sort; need uniq; need head; need date

G="bin/p1_ui_spec_gate_v1.sh"
[ -f "$G" ] || { echo "[ERR] missing $G"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$G" "${G}.bak_syntax_${TS}"
echo "[BACKUP] ${G}.bak_syntax_${TS}"

cat > "$G" <<'SH2'
#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SPEC="${VSP_UI_SPEC:-/home/test/Data/SECURITY_BUNDLE/ui/spec/ui_spec_2025.json}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need awk; need sort; need uniq; need head; need sed; need mktemp

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*" >&2; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*" >&2; ERR=$((ERR+1)); }

tmp="$(mktemp -d /tmp/vsp_ui_spec_gate_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

[ -f "$SPEC" ] || { echo "[ERR] missing SPEC: $SPEC"; exit 2; }

python3 - "$SPEC" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],"r",encoding="utf-8"))
print("SPEC_NAME=", s.get("name"))
print("TABS=", len(s.get("tabs") or []))
print("API=", len(s.get("api") or []))
PY

fetch(){
  local url="$1" out="$2"
  curl -fsS -L "$url" -o "$out"
}

extract_assets_and_check_dupe(){
  local html="$1"
  grep -oE '/static/[^"]+\.js(\?v=[0-9]+)?' "$html" | sed 's/\?v=.*$//' > "$tmp/js.txt" || true
  grep -oE '/static/[^"]+\.css(\?v=[0-9]+)?' "$html" | sed 's/\?v=.*$//' > "$tmp/css.txt" || true

  if [ -s "$tmp/js.txt" ]; then
    sort "$tmp/js.txt" > "$tmp/js.sorted"
    if uniq -d "$tmp/js.sorted" | head -n 1 >/dev/null; then
      err "duplicate JS detected: $(uniq -d "$tmp/js.sorted" | head -n 8 | tr '\n' ' ')"
    else
      ok "no duplicate JS"
    fi
  else
    warn "no JS assets detected (pattern may differ)"
  fi

  if [ -s "$tmp/css.txt" ]; then
    sort "$tmp/css.txt" > "$tmp/css.sorted"
    if uniq -d "$tmp/css.sorted" | head -n 1 >/dev/null; then
      err "duplicate CSS detected: $(uniq -d "$tmp/css.sorted" | head -n 8 | tr '\n' ' ')"
    else
      ok "no duplicate CSS"
    fi
  else
    warn "no CSS assets detected (pattern may differ)"
  fi
}

check_required_markers(){
  local html="$1" req_json="$2" tab="$3"
  python3 - "$html" "$req_json" "$tab" <<'PY'
import json,sys
html=open(sys.argv[1],"r",encoding="utf-8",errors="replace").read()
req=json.loads(sys.argv[2])
tab=sys.argv[3]
missing=[m for m in req if m not in html]
if missing:
  print(f"[ERR] {tab}: missing required markers:", missing[:20])
  sys.exit(2)
print(f"[OK] {tab}: required markers present ({len(req)})")
PY
}

check_optional_markers(){
  local html="$1" opt_json="$2" tab="$3"
  python3 - "$html" "$opt_json" "$tab" <<'PY'
import json,sys
html=open(sys.argv[1],"r",encoding="utf-8",errors="replace").read()
opt=json.loads(sys.argv[2])
tab=sys.argv[3]
missing=[m for m in opt if m not in html]
if missing:
  print(f"[WARN] {tab}: missing optional markers:", missing[:20])
  sys.exit(0)
print(f"[OK] {tab}: optional markers present ({len(opt)})")
PY
}

check_api_keys_any(){
  local url="$1" required="$2" keys_any="$3"
  local J=""
  if ! J="$(curl -fsS -L "$url" 2>/dev/null)"; then
    if [ "$required" = "true" ]; then err "API required but not reachable: $url"; else warn "API optional not reachable: $url"; fi
    return 0
  fi
  python3 - "$url" "$required" "$keys_any" <<'PY' <<<"$J"
import json,sys
url=sys.argv[1]; required=(sys.argv[2].lower()=="true")
keys=json.loads(sys.argv[3])
try:
  j=json.loads(sys.stdin.read() or "{}")
except Exception as e:
  if required:
    print("[ERR] API invalid JSON:", url, e); sys.exit(2)
  print("[WARN] API invalid JSON (optional):", url, e); sys.exit(0)

present=[k for k in keys if k in j]
if not present:
  if required:
    print("[ERR] API missing all expected keys:", url, "expected any of", keys); sys.exit(2)
  print("[WARN] API (optional) missing keys:", url, "expected any of", keys); sys.exit(0)
print("[OK] API schema keys ok:", url, "present_any=", present)
PY
}

echo "== [1] Tabs: HTML reachability + dup assets + markers =="
python3 - "$SPEC" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],"r",encoding="utf-8"))
for t in s.get("tabs") or []:
  print(t["path"], str(bool(t.get("required"))).lower(),
        json.dumps(t.get("markers_required") or []),
        json.dumps(t.get("markers_optional") or []))
PY | while read -r path required req opt; do
  url="${BASE}${path}"
  out="$tmp$(echo "$path" | tr '/' '_').html"

  if fetch "$url" "$out"; then
    ok "reachable: $path"
    extract_assets_and_check_dupe "$out" || true

    tab="$(basename "$path")"
    if check_required_markers "$out" "$req" "$tab"; then
      : # ok already printed
    else
      if [ "$required" = "true" ]; then err "$tab: missing required markers"; else warn "$tab: missing required markers (optional tab)"; fi
    fi

    check_optional_markers "$out" "$opt" "$tab" || true
  else
    if [ "$required" = "true" ]; then err "tab not reachable: $path"; else warn "tab not reachable (optional): $path"; fi
  fi
done

echo "== [2] API: schema keys =="
python3 - "$SPEC" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],"r",encoding="utf-8"))
for a in s.get("api") or []:
  print(a["path"], str(bool(a.get("required"))).lower(), json.dumps(a.get("json_keys_any") or []))
PY | while read -r path required keys_any; do
  check_api_keys_any "${BASE}${path}" "$required" "$keys_any" || true
done

echo "== [3] Summary =="
echo "OK=$OK WARN=$WARN ERR=$ERR"
[ "$ERR" -eq 0 ] || exit 2
SH2

chmod +x "$G"
bash -n "$G" && echo "[OK] bash -n OK" || { echo "[ERR] bash -n failed"; exit 2; }

echo "[OK] patched: $G"
echo "[NEXT] run: bash bin/p1_ui_spec_gate_v1.sh"
