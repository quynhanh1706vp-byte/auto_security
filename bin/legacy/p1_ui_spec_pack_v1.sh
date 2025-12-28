#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need curl; need grep; need sed; need awk; need date; need mkdir; need head; need sort; need uniq

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"

mkdir -p spec bin

###############################################################################
# (A) ui_spec_2025.json (skeleton, required items = những cái tối thiểu để gate)
###############################################################################
cat > spec/ui_spec_2025.json <<'JSON'
{
  "name": "VSP UI Spec 2025 (P1 skeleton)",
  "base_env": "VSP_UI_BASE",
  "tabs": [
    {
      "path": "/vsp5",
      "required": true,
      "markers_required": [
        "id=\"vsp-dashboard-main\"",
        "data-testid=\"kpi_total\"",
        "data-testid=\"kpi_critical\"",
        "data-testid=\"kpi_high\"",
        "data-testid=\"kpi_medium\"",
        "data-testid=\"kpi_low\"",
        "data-testid=\"kpi_info_trace\""
      ],
      "markers_optional": [
        "data-testid=\"kpi_posture_score\"",
        "data-testid=\"chart_trend\"",
        "data-testid=\"tbl_top_findings\""
      ]
    },
    {
      "path": "/runs",
      "required": true,
      "markers_required": ["id=\"vsp-runs-main\""],
      "markers_optional": ["data-testid=\"runs_filters\"", "data-testid=\"runs_export\""]
    },
    {
      "path": "/data_source",
      "required": true,
      "markers_required": ["id=\"vsp-data-source-main\""],
      "markers_optional": ["data-testid=\"ds_filters\"", "data-testid=\"ds_table\""]
    },
    {
      "path": "/settings",
      "required": true,
      "markers_required": ["id=\"vsp-settings-main\""],
      "markers_optional": ["data-testid=\"profile_manager\"", "data-testid=\"tool_toggles\""]
    },
    {
      "path": "/rule_overrides",
      "required": true,
      "markers_required": ["id=\"vsp-rule-overrides-main\""],
      "markers_optional": ["data-testid=\"override_editor\"", "data-testid=\"override_apply\""]
    }
  ],
  "api": [
    {
      "path": "/api/vsp/rid_latest",
      "required": true,
      "json_keys_any": ["rid"]
    },
    {
      "path": "/api/vsp/runs?limit=20&offset=0",
      "required": true,
      "json_keys_any": ["runs", "total"]
    },
    {
      "path": "/api/vsp/top_findings_v1?limit=5",
      "required": false,
      "json_keys_any": ["items", "total"]
    },
    {
      "path": "/api/vsp/trend_v1",
      "required": false,
      "json_keys_any": ["points"]
    }
  ]
}
JSON
ok "wrote spec/ui_spec_2025.json"

###############################################################################
# (B) Gate script: soi trùng JS/CSS, thiếu marker, API schema keys
###############################################################################
cat > bin/p1_ui_spec_gate_v1.sh <<'SH2'
#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SPEC="${VSP_UI_SPEC:-/home/test/Data/SECURITY_BUNDLE/ui/spec/ui_spec_2025.json}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need awk; need sort; need uniq; need head; need sed

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
  # JS
  grep -oE '/static/[^"]+\.js(\?v=[0-9]+)?' "$html" | sed 's/\?v=.*$//' > "$tmp/js.txt" || true
  # CSS
  grep -oE '/static/[^"]+\.css(\?v=[0-9]+)?' "$html" | sed 's/\?v=.*$//' > "$tmp/css.txt" || true

  if [ -s "$tmp/js.txt" ]; then
    sort "$tmp/js.txt" > "$tmp/js.sorted"
    if uniq -d "$tmp/js.sorted" | head -n 1 >/dev/null; then
      err "duplicate JS detected: $(uniq -d "$tmp/js.sorted" | head -n 5 | tr '\n' ' ')"
    else
      ok "no duplicate JS"
    fi
  else
    warn "no JS assets detected (pattern may differ)"
  fi

  if [ -s "$tmp/css.txt" ]; then
    sort "$tmp/css.txt" > "$tmp/css.sorted"
    if uniq -d "$tmp/css.sorted" | head -n 1 >/dev/null; then
      err "duplicate CSS detected: $(uniq -d "$tmp/css.sorted" | head -n 5 | tr '\n' ' ')"
    else
      ok "no duplicate CSS"
    fi
  else
    warn "no CSS assets detected (pattern may differ)"
  fi
}

check_markers(){
  local html="$1" required="$2" optional="$3" tabname="$4"
  # required markers
  python3 - "$html" "$required" "$tabname" <<'PY'
import json,sys
html=open(sys.argv[1],"r",encoding="utf-8",errors="replace").read()
req=json.loads(sys.argv[2])
tab=sys.argv[3]
missing=[m for m in req if m not in html]
if missing:
  print(f"[ERR] {tab}: missing required markers:", missing[:10])
  sys.exit(2)
print(f"[OK] {tab}: required markers present ({len(req)})")
PY
  # optional markers -> WARN if missing
  python3 - "$html" "$optional" "$tabname" <<'PY'
import json,sys
html=open(sys.argv[1],"r",encoding="utf-8",errors="replace").read()
opt=json.loads(sys.argv[2])
tab=sys.argv[3]
missing=[m for m in opt if m not in html]
if missing:
  print(f"[WARN] {tab}: missing optional markers:", missing[:10])
  sys.exit(0)
print(f"[OK] {tab}: optional markers present ({len(opt)})")
PY
}

check_api_keys_any(){
  local url="$1" required="$2" keys_any="$3"
  if ! J="$(curl -fsS -L "$url" 2>/dev/null)"; then
    if [ "$required" = "true" ]; then err "API required but not reachable: $url"; else warn "API optional not reachable: $url"; fi
    return 0
  fi
  python3 - "$url" "$required" "$keys_any" <<'PY'
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
PY <<<"$J"
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
  if fetch "$url" "$out" 2>/dev/null; then
    ok "reachable: $path"
    extract_assets_and_check_dupe "$out" || true
    # markers check:
    if python3 - "$out" "$req" "$(basename "$path")" <<'PY' >/dev/null 2>&1
import json,sys; html=open(sys.argv[1],"r",encoding="utf-8",errors="replace").read()
req=json.loads(sys.argv[2]); missing=[m for m in req if m not in html]
sys.exit(2 if missing else 0)
PY
    then
      ok "$(basename "$path"): required markers ok"
    else
      if [ "$required" = "true" ]; then err "$(basename "$path"): missing required markers"; else warn "$(basename "$path"): missing required markers (optional tab)"; fi
    fi
    # optional markers as warn
    python3 - "$out" "$opt" "$(basename "$path")" <<'PY' || true
import json,sys
html=open(sys.argv[1],"r",encoding="utf-8",errors="replace").read()
opt=json.loads(sys.argv[2]); tab=sys.argv[3]
missing=[m for m in opt if m not in html]
if missing:
  print(f"[WARN] {tab}: missing optional markers:", missing[:10])
else:
  print(f"[OK] {tab}: optional markers ok ({len(opt)})")
PY
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
chmod +x bin/p1_ui_spec_gate_v1.sh
ok "wrote bin/p1_ui_spec_gate_v1.sh"

###############################################################################
# (C) Gate: detect bad app reassign patterns (quick fail)
###############################################################################
cat > bin/p1_gate_wsgi_no_app_reassign_v1.sh <<'SH3'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

bad=0

echo "== check: app = application (should not exist) =="
if grep -RIn --line-number -E '^\s*app\s*=\s*application\s*$' "$F" >/dev/null; then
  grep -RIn --line-number -E '^\s*app\s*=\s*application\s*$' "$F" | head -n 50
  bad=1
else
  echo "[OK] no 'app = application'"
fi

echo "== check: app = None (high risk) =="
if grep -RIn --line-number -E '^\s*app\s*=\s*None\s*$' "$F" >/dev/null; then
  grep -RIn --line-number -E '^\s*app\s*=\s*None\s*$' "$F" | head -n 50
  bad=1
else
  echo "[OK] no 'app = None'"
fi

echo "== check: wrapper assigns to app (prefer application = wrap(application)) =="
if grep -RIn --line-number -E '^\s*app\s*=\s*[A-Za-z_][A-Za-z0-9_\.]*\(\s*app\b' "$F" >/dev/null; then
  grep -RIn --line-number -E '^\s*app\s*=\s*[A-Za-z_][A-Za-z0-9_\.]*\(\s*app\b' "$F" | head -n 80
  bad=1
else
  echo "[OK] no 'app = wrap(app)' pattern"
fi

[ "$bad" -eq 0 ] || { echo "[ERR] wsgi app reassign patterns found"; exit 2; }
echo "[OK] gate passed"
SH3
chmod +x bin/p1_gate_wsgi_no_app_reassign_v1.sh
ok "wrote bin/p1_gate_wsgi_no_app_reassign_v1.sh"

###############################################################################
# (D) Patch script: normalize app/application safely (conservative)
###############################################################################
cat > bin/p1_refactor_wsgi_app_application_v1.sh <<'SH4'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_app_application_${TS}"
echo "[BACKUP] ${F}.bak_app_application_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

orig=s

# 1) Remove dangerous rebind: app = application
s = re.sub(r'(?m)^(\s*)app\s*=\s*application\s*$', r'\1# VSP_P1: removed unsafe "app = application" (keep Flask app stable)', s)

# 2) Remove dangerous: app = None
s = re.sub(r'(?m)^(\s*)app\s*=\s*None\s*$', r'\1# VSP_P1: removed unsafe "app = None"\n\1_app_disabled = None', s)

# 3) Redirect wrapper patterns: app = wrap(app...)  -> application = wrap(application...)
def _wrap_line(m):
    indent=m.group(1); fn=m.group(2)
    return f"{indent}# VSP_P1: redirect wrapper from app->application\n{indent}application = {fn}(application"
s = re.sub(r'(?m)^(\s*)app\s*=\s*([A-Za-z_][\w\.]*)\(\s*app\b', _wrap_line, s)

# 4) Ensure stable exports appended once
marker = "VSP_P1_EXPORT_APP_APPLICATION_V1"
if marker not in s:
    s += "\n\n# --- {} (do not edit below) ---\n".format(marker)
    s += "try:\n    flask_app\nexcept NameError:\n    flask_app = globals().get('app')\n"
    s += "try:\n    application\nexcept NameError:\n    application = flask_app\n"
    s += "# Keep legacy name 'app' as Flask for blueprints/routes; gunicorn should use 'application'\n"
    s += "app = flask_app\n"

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched wsgi (conservative)")
else:
    print("[WARN] no changes applied (patterns not found)")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

echo "[NEXT] 1) run gate: bash bin/p1_gate_wsgi_no_app_reassign_v1.sh"
echo "[NEXT] 2) restart service if needed: systemctl restart vsp-ui-8910.service"
echo "[NEXT] 3) run UI spec gate: bash bin/p1_ui_spec_gate_v1.sh"
SH4
chmod +x bin/p1_refactor_wsgi_app_application_v1.sh
ok "wrote bin/p1_refactor_wsgi_app_application_v1.sh"

echo
ok "P1 pack ready."
echo "Run next:"
echo "  (1) bash bin/p1_refactor_wsgi_app_application_v1.sh"
echo "  (2) bash bin/p1_gate_wsgi_no_app_reassign_v1.sh"
echo "  (3) systemctl restart vsp-ui-8910.service   # if you run systemd"
echo "  (4) bash bin/p1_ui_spec_gate_v1.sh"
