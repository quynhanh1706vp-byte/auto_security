#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

# candidate dirs that release card may read from
DIRS=(
  "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases"
  "/home/test/Data/SECURITY_BUNDLE/ui/out/releases"
  "/home/test/Data/SECURITY_BUNDLE/out_ci/releases"
  "/home/test/Data/SECURITY_BUNDLE/out/releases"
)

echo "== [0] write release_latest.json to all common roots =="
for d in "${DIRS[@]}"; do
  mkdir -p "$d"
  cat > "$d/release_latest.json" <<'JSON'
{
  "ts": "2025-12-21T22:15:00+07:00",
  "package": "out_ci/releases/THIS_FILE_DOES_NOT_EXIST.tgz",
  "sha": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
}
JSON
  echo "[OK] wrote: $d/release_latest.json"
done

echo
echo "== [1] local JSON sanity =="
python3 - <<'PY'
import json, glob
paths = sorted(glob.glob("/home/test/Data/SECURITY_BUNDLE/**/releases/release_latest.json", recursive=True))
print("found:", len(paths))
for p in paths[:12]:
    j=json.load(open(p,"r",encoding="utf-8"))
    print("-", p, "keys=", list(j.keys()), "package=", j.get("package"))
PY

echo
echo "== [2] HTTP sanity (must be 200 for at least one) =="
set +e
for u in \
  "$BASE/out_ci/releases/release_latest.json" \
  "$BASE/out/releases/release_latest.json" \
  "$BASE/api/vsp/release_latest.json"
do
  echo "-- $u"
  curl -sS -D /tmp/_rel_hdr.txt -o /tmp/_rel_body.txt "$u"
  head -n 1 /tmp/_rel_hdr.txt | sed 's/\r$//'
  echo "BODY_HEAD: $(head -c 120 /tmp/_rel_body.txt | tr '\n' ' ')"
  echo
done
set -e

echo "== DONE =="
echo "Reload /runs (Ctrl+Shift+R) then click Refresh on Current Release card."
