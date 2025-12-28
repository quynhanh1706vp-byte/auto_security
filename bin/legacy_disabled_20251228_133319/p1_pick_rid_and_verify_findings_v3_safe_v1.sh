#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
FALLBACK="${1:-RUN_20251120_130310}"

TMP="$(mktemp -d /tmp/vsp_pickrid.XXXXXX)"
RUNS_JSON="$TMP/runs_v3.json"

echo "[BASE] $BASE"
echo "[TMP]  $TMP"

# 1) fetch runs_v3 (NO -f to avoid empty pipe)
if ! curl -sS "$BASE/api/ui/runs_v3?limit=80&offset=0" > "$RUNS_JSON"; then
  echo "[WARN] curl runs_v3 failed -> fallback RID=$FALLBACK"
  RID="$FALLBACK"
else
  # 2) pick first nonzero rid safely
  RID="$(python3 - "$RUNS_JSON" "$FALLBACK" <<'PY'
import sys, json
fp, fallback = sys.argv[1], sys.argv[2]
try:
    s = open(fp, "r", encoding="utf-8", errors="replace").read().strip()
    if not s or not s.startswith("{"):
        print(fallback); sys.exit(0)
    j = json.loads(s)
    for it in j.get("items", []):
        if it.get("has_findings") and int(it.get("findings_total", 0)) > 0:
            print(it.get("rid")); sys.exit(0)
    print(fallback)
except Exception:
    print(fallback)
PY
)"
fi

echo "[RID] $RID"

# 3) verify findings_v3 (NO head cut -> avoid SIGPIPE)
echo "== findings_v3 sample =="
curl -sS "$BASE/api/ui/findings_v3?rid=$RID&limit=1&offset=0" | python3 - <<'PY'
import sys, json
s=sys.stdin.read().strip()
print(s[:1200] + ("..." if len(s)>1200 else ""))
try:
    j=json.loads(s)
    print("ok=", j.get("ok"), " total=", j.get("total"), " counts.TOTAL=", (j.get("counts") or {}).get("TOTAL"))
except Exception as e:
    print("[PARSE_ERR]", e)
PY

echo "[DONE] Now hard-refresh /data_source (Ctrl+Shift+R) and pick RID above."
