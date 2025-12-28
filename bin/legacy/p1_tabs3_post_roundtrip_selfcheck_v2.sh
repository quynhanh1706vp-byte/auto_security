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

  # restore settings (normalize payload shape)
  if [ -f "$TMP/old_settings.json" ]; then
    python3 - "$TMP/old_settings.json" "$TMP/restore_settings_payload.json" <<'PY'
import json, sys
src, out = sys.argv[1], sys.argv[2]
j = json.load(open(src, "r", encoding="utf-8"))
# server expects {"settings": {...}}
payload = j if isinstance(j, dict) and "settings" in j else {"settings": (j if isinstance(j, dict) else {})}
json.dump(payload, open(out, "w", encoding="utf-8"), ensure_ascii=False)
PY
    curl -fsS -X POST "$BASE/api/ui/settings_v2" -H 'Content-Type: application/json' \
      --data-binary "@$TMP/restore_settings_payload.json" >/dev/null || true
  fi

  # restore rules (expects {"rules":[...]})
  if [ -f "$TMP/old_rules.json" ]; then
    python3 - "$TMP/old_rules.json" "$TMP/restore_rules_payload.json" <<'PY'
import json, sys
src, out = sys.argv[1], sys.argv[2]
j = json.load(open(src, "r", encoding="utf-8"))
payload = j if isinstance(j, dict) and "rules" in j else {"rules": []}
json.dump(payload, open(out, "w", encoding="utf-8"), ensure_ascii=False)
PY
    curl -fsS -X POST "$BASE/api/ui/rule_overrides_v2" -H 'Content-Type: application/json' \
      --data-binary "@$TMP/restore_rules_payload.json" >/dev/null || true
  fi

  rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

get_json(){
  local path="$1" out="$2"
  curl -fsS "$BASE$path" > "$out"
  python3 - "$path" "$out" <<'PY'
import json, sys
path, fn = sys.argv[1], sys.argv[2]
j = json.load(open(fn, "r", encoding="utf-8"))
if not j.get("ok", False):
  print("[ERR] GET", path, "ok!=true", j)
  sys.exit(2)
print("[OK] GET", path, "ok:true")
PY
}

post_json(){
  local path="$1" in="$2"
  local out="$TMP/post_resp.json"
  curl -fsS -X POST "$BASE$path" -H 'Content-Type: application/json' --data-binary "@$in" > "$out"
  python3 - "$path" "$out" <<'PY'
import json, sys
path, fn = sys.argv[1], sys.argv[2]
j = json.load(open(fn, "r", encoding="utf-8"))
if not j.get("ok", False):
  print("[ERR] POST", path, "ok!=true", j)
  sys.exit(2)
print("[OK] POST", path, "ok:true")
PY
}

# 1) Discover latest RID
curl -fsS "$BASE/api/ui/runs_v2?limit=1" > "$TMP/runs.json"
RID="$(python3 - "$TMP/runs.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1], "r", encoding="utf-8"))
items = j.get("items") or []
print(items[0].get("rid","") if items else "")
PY
)"
[ -n "$RID" ] || { echo "[ERR] cannot discover RID from /api/ui/runs_v2"; exit 2; }
echo "[RID] $RID"

# 2) Backup current settings/rules (store the raw sub-objects we got)
get_json "/api/ui/settings_v2" "$TMP/settings_get.json"
python3 - "$TMP/settings_get.json" "$TMP/old_settings.json" <<'PY'
import json, sys
src, out = sys.argv[1], sys.argv[2]
j = json.load(open(src, "r", encoding="utf-8"))
# keep exactly what server returns in "settings" (could be {} or {"settings":{...}})
old = j.get("settings") or {}
json.dump(old, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("[OK] saved old_settings.json")
PY

get_json "/api/ui/rule_overrides_v2" "$TMP/rules_get.json"
python3 - "$TMP/rules_get.json" "$TMP/old_rules.json" <<'PY'
import json, sys
src, out = sys.argv[1], sys.argv[2]
j = json.load(open(src, "r", encoding="utf-8"))
old = (j.get("data") or {"rules":[]})
json.dump(old, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("[OK] saved old_rules.json")
PY

# 3) POST test settings (harmless)
cat > "$TMP/new_settings.json" <<'JSON'
{
  "settings": {
    "degrade_graceful": true,
    "timeouts": { "kics_sec": 900, "trivy_sec": 900, "codeql_sec": 1800 }
  }
}
JSON
post_json "/api/ui/settings_v2" "$TMP/new_settings.json"

# 4) POST test rules (no-op)
cat > "$TMP/new_rules.json" <<'JSON'
{ "rules": [] }
JSON
post_json "/api/ui/rule_overrides_v2" "$TMP/new_rules.json"

# 5) Apply rules to RID (best-effort)
APPLY_OK=0
for ep in "/api/ui/rule_overrides_apply_v2" "/api/ui/rules_apply_v2" "/api/ui/rule_overrides_apply"; do
  if curl -fsS -o "$TMP/apply_resp.json" -X POST "$BASE$ep" -H 'Content-Type: application/json' \
      --data-binary "{\"rid\":\"$RID\"}" ; then
    if python3 - "$TMP/apply_resp.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1], "r", encoding="utf-8"))
sys.exit(0 if j.get("ok") is True else 3)
PY
    then
      echo "[OK] APPLY $ep ok:true"
      APPLY_OK=1
      break
    else
      echo "[WARN] APPLY $ep ok!=true (response in $TMP/apply_resp.json)"
    fi
  else
    echo "[WARN] APPLY endpoint not working: $ep"
  fi
done

if [ "$APPLY_OK" -eq 0 ]; then
  echo "[WARN] apply endpoint not confirmed (but settings/rules POST ok)."
fi

echo "[DONE] POST roundtrip selfcheck OK (will auto-restore previous data)."
