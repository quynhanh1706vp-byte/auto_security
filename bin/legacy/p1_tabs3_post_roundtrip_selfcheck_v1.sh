#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need mktemp; need date

echo "[BASE] $BASE"

TMP="$(mktemp -d /tmp/vsp_post_roundtrip.XXXXXX)"
cleanup(){
  echo "[CLEANUP] restoring previous settings/rules (best-effort)"
  if [ -f "$TMP/old_settings.json" ]; then
    curl -fsS -X POST "$BASE/api/ui/settings_v2" -H 'Content-Type: application/json' --data-binary "@$TMP/old_settings.json" >/dev/null || true
  fi
  if [ -f "$TMP/old_rules.json" ]; then
    curl -fsS -X POST "$BASE/api/ui/rule_overrides_v2" -H 'Content-Type: application/json' --data-binary "@$TMP/old_rules.json" >/dev/null || true
  fi
  rm -rf "$TMP" || true
}
trap cleanup EXIT

get_json(){
  local path="$1" out="$2"
  curl -fsS "$BASE$path" > "$out"
  python3 - <<PY
import json,sys
j=json.load(open("$out","r",encoding="utf-8"))
if not j.get("ok", False):
  print("[ERR] GET $path ok!=true", j)
  sys.exit(2)
print("[OK] GET $path ok:true")
PY
}

post_json(){
  local path="$1" in="$2"
  local out="$TMP/post_resp.json"
  curl -fsS -X POST "$BASE$path" -H 'Content-Type: application/json' --data-binary "@$in" > "$out"
  python3 - <<PY
import json,sys
j=json.load(open("$out","r",encoding="utf-8"))
if not j.get("ok", False):
  print("[ERR] POST $path ok!=true", j)
  sys.exit(2)
print("[OK] POST $path ok:true")
PY
}

# --- 1) Discover latest RID ---
curl -fsS "$BASE/api/ui/runs_v2?limit=1" > "$TMP/runs.json"
RID="$(python3 - <<'PY'
import json
j=json.load(open("'"$TMP/runs.json"'",encoding="utf-8"))
items=j.get("items") or []
print(items[0].get("rid","") if items else "")
PY
)"
[ -n "$RID" ] || { echo "[ERR] cannot discover RID from /api/ui/runs_v2"; exit 2; }
echo "[RID] $RID"

# --- 2) Backup current settings/rules ---
get_json "/api/ui/settings_v2" "$TMP/settings_get.json"
python3 - <<PY
import json
j=json.load(open("$TMP/settings_get.json",encoding="utf-8"))
# server GET returns {"settings": {...}} in j["settings"]
old = j.get("settings") or {}
json.dump(old, open("$TMP/old_settings.json","w",encoding="utf-8"), ensure_ascii=False, indent=2)
print("[OK] saved old_settings.json keys=", list(old.keys())[:8])
PY

get_json "/api/ui/rule_overrides_v2" "$TMP/rules_get.json"
python3 - <<PY
import json
j=json.load(open("$TMP/rules_get.json",encoding="utf-8"))
# server GET returns {"data": {"rules":[...]}}
old = j.get("data") or {"rules":[]}
json.dump(old, open("$TMP/old_rules.json","w",encoding="utf-8"), ensure_ascii=False, indent=2)
print("[OK] saved old_rules.json rules_n=", len((old.get("rules") or [])))
PY

# --- 3) POST test settings (toggle a harmless field) ---
cat > "$TMP/new_settings.json" <<'JSON'
{
  "settings": {
    "degrade_graceful": true,
    "timeouts": { "kics_sec": 900, "trivy_sec": 900, "codeql_sec": 1800 }
  }
}
JSON
post_json "/api/ui/settings_v2" "$TMP/new_settings.json"

# --- 4) POST test rules (keep empty / no-op) ---
cat > "$TMP/new_rules.json" <<'JSON'
{ "rules": [] }
JSON
post_json "/api/ui/rule_overrides_v2" "$TMP/new_rules.json"

# --- 5) Apply rules to RID (best-effort: try common endpoints) ---
APPLY_OK=0
for ep in "/api/ui/rule_overrides_apply_v2" "/api/ui/rules_apply_v2" "/api/ui/rule_overrides_apply"; do
  if curl -fsS -o "$TMP/apply_resp.json" -X POST "$BASE$ep" -H 'Content-Type: application/json' --data-binary "{\"rid\":\"$RID\"}" ; then
    python3 - <<PY
import json,sys
j=json.load(open("$TMP/apply_resp.json",encoding="utf-8"))
if j.get("ok") is True:
  print("[OK] APPLY", "$ep", "ok:true")
  sys.exit(0)
print("[WARN] APPLY", "$ep", "ok!=true", j)
sys.exit(3)
PY
    APPLY_OK=1
    break
  else
    echo "[WARN] APPLY endpoint not working: $ep"
  fi
done

if [ "$APPLY_OK" -eq 0 ]; then
  echo "[WARN] apply endpoint not confirmed (but settings/rules POST ok)."
fi

echo "[DONE] POST roundtrip selfcheck OK (will auto-restore previous data)."
