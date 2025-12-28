#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

tmp="/tmp/vsp_cleanpack_selfcheck_$$"
mkdir -p "$tmp"
export VSP_TMPDIR="$tmp"

echo "== [0] basic health =="
curl -fsS -I "$BASE/vsp5" | sed -n '1,12p'
curl -fsS "$BASE/vsp5" | head -n 3

echo
echo "== [1] rid_latest_gate_root (must have X-VSP-RIDPICK: ENDWRAP_V4) =="
curl -fsS -D "$tmp/rid.h" -o "$tmp/rid.json" "$BASE/api/vsp/rid_latest_gate_root"
grep -i '^X-VSP-RIDPICK:' "$tmp/rid.h" || { echo "[ERR] missing X-VSP-RIDPICK header"; sed -n '1,30p' "$tmp/rid.h"; exit 2; }

RID="$(python3 - <<'PY'
import os, json
tmp=os.environ["VSP_TMPDIR"]
p=f"{tmp}/rid.json"
j=json.load(open(p,"r",encoding="utf-8",errors="ignore"))
print(j.get("rid",""))
PY
)"
[ -n "$RID" ] || { echo "[ERR] empty RID"; echo "--- rid.json ---"; cat "$tmp/rid.json" || true; exit 2; }
echo "RID=$RID"

echo
echo "== [2] top_findings_v4 (robust) =="
Q_RID="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$RID")"
URL="$BASE/api/vsp/top_findings_v4?rid=$Q_RID&limit=5"
echo "URL=$URL"

ok=0
for i in 1 2 3 4 5; do
  curl -sS -D "$tmp/tf.h" -o "$tmp/tf.body" "$URL" || true
  sz=$(wc -c < "$tmp/tf.body" || echo 0)
  ct=$(grep -i '^Content-Type:' "$tmp/tf.h" | head -n 1 | tr -d '\r' || true)
  code=$(awk 'NR==1{print $2}' "$tmp/tf.h" 2>/dev/null || true)

  echo "[try#$i] code=${code:-?} size=$sz ${ct:-}"
  if [ "$sz" -ge 2 ]; then
    head1="$(head -c 1 "$tmp/tf.body" || true)"
    if [ "$head1" = "{" ]; then ok=1; break; fi
  fi
  sleep 0.3
done

if [ "$ok" -ne 1 ]; then
  echo "[ERR] top_findings_v4 returned empty/non-json."
  echo "--- headers ---"; sed -n '1,60p' "$tmp/tf.h" || true
  echo "--- body (first 300 bytes) ---"; head -c 300 "$tmp/tf.body" | cat -A || true; echo
  exit 2
fi

python3 - <<'PY'
import os, json
tmp=os.environ["VSP_TMPDIR"]
p=f"{tmp}/tf.body"
j=json.load(open(p,"r",encoding="utf-8",errors="ignore"))
if not j.get("ok"):
    raise SystemExit("[ERR] ok=false: %r" % (j,))
items=j.get("items") or []
if len(items) < 1:
    raise SystemExit("[ERR] items empty: %r" % (j,))
print("[OK] top_findings_v4 ok, items=", len(items), "source=", j.get("source"))
print("sample:", items[0])
PY

echo
echo "== [DONE] Commercial selfcheck passed =="
echo "Open: $BASE/vsp5  (debug-only overlays should be ?debug=1)"
