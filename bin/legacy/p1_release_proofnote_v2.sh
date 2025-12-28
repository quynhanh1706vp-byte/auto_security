#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need python3; need mkdir; need sha256sum; need ls; need awk

BASE="http://127.0.0.1:8910"
J="$(curl -fsS "$BASE/api/vsp/release_latest")"

RID="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("rid",""))' <<<"$J")"
[ -n "$RID" ] || { echo "[ERR] rid missing in release_latest"; echo "$J"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p releases
OUT="releases/PROOF_${RID}_${TS}.md"

# Download zip to verify content-length and sha
ZIP="/tmp/${RID}.zip"
curl -fsS "$BASE/api/vsp/release_download?rid=$RID" -o "$ZIP"
ZSIZE="$(ls -l "$ZIP" | awk '{print $5}')"
ZSHA="$(sha256sum "$ZIP" | awk '{print $1}')"

python3 - "$OUT" "$ZSIZE" "$ZSHA" <<'PY'
import json,sys,datetime
out=sys.argv[1]
zsize=sys.argv[2]
zsha=sys.argv[3]
j=json.loads(open("/dev/stdin","r",encoding="utf-8").read())
rid=j.get("rid","")
ts=j.get("ts","")
with open(out,"w",encoding="utf-8") as f:
    f.write("# VSP UI Release Proof\n\n")
    f.write(f"- RID: `{rid}`\n")
    f.write(f"- Proof generated at: `{datetime.datetime.now().isoformat(timespec='seconds')}`\n")
    f.write(f"- API ts: `{ts}`\n\n")
    f.write("## Package\n")
    f.write(f"- package_path: `{j.get('package_path')}`\n")
    f.write(f"- package_sha256 (declared): `{j.get('package_sha256')}`\n")
    f.write(f"- manifest_path: `{j.get('manifest_path')}`\n")
    f.write(f"- run_dir: `{j.get('run_dir')}`\n")
    f.write(f"- notes: {j.get('notes')}\n\n")
    f.write("## Links\n")
    f.write(f"- download_url: `{j.get('download_url')}`\n")
    f.write(f"- audit_url: `{j.get('audit_url')}`\n\n")
    f.write("## Verification\n")
    f.write(f"- downloaded_zip: `{rid}.zip`\n")
    f.write(f"- downloaded_size_bytes: `{zsize}`\n")
    f.write(f"- downloaded_sha256: `{zsha}`\n")
PY <<<"$J"

echo "[OK] wrote $OUT"
echo "[OK] downloaded $ZIP size=$ZSIZE sha256=$ZSHA"
echo "[SEND] Download: /api/vsp/release_download?rid=$RID"
echo "[SEND] Audit:    /api/vsp/release_audit?rid=$RID"
