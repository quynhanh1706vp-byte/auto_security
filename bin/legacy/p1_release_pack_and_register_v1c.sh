#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need zip; need systemctl; need curl; need mkdir; need ls; need wc

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
REL_DIR="/home/test/Data/SECURITY_BUNDLE/ui/releases"
mkdir -p "$REL_DIR"

RID="${1:-}"
if [ -z "$RID" ]; then
  RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("rid") or "").strip())')"
fi
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }
echo "[RID] $RID"

RUN_DIR=""
for d in \
  "/home/test/Data/SECURITY_BUNDLE/out/$RID" \
  "/home/test/Data/SECURITY_BUNDLE/out_ci/$RID" \
  "/home/test/Data/SECURITY_BUNDLE/ui/out/$RID" \
  "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/$RID"
do
  [ -d "$d" ] && RUN_DIR="$d" && break
done
[ -n "$RUN_DIR" ] || { echo "[ERR] run dir not found for RID=$RID"; exit 2; }
echo "[RUN_DIR] $RUN_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
PKG="$REL_DIR/VSP_RELEASE_${RID}_${TS}.zip"
MAN="$REL_DIR/VSP_RELEASE_${RID}_${TS}.manifest.json"

echo "== [1] pack zip =="
tmp="$(mktemp -d /tmp/vsp_relpack_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/payload"

[ -d "$RUN_DIR/reports" ] && mkdir -p "$tmp/payload/reports" && cp -a "$RUN_DIR/reports/." "$tmp/payload/reports/" || true

for f in \
  "run_gate_summary.json" \
  "reports/run_gate_summary.json" \
  "findings_unified.json" \
  "reports/findings_unified.json" \
  "reports/findings_unified.csv" \
  "reports/findings_unified.sarif" \
  "SUMMARY.txt" \
  "run_manifest.json" \
  "run_gate.json"
do
  [ -f "$RUN_DIR/$f" ] || continue
  mkdir -p "$tmp/payload/$(dirname "$f")"
  cp -a "$RUN_DIR/$f" "$tmp/payload/$f"
done

( cd "$tmp/payload" && zip -qr "$PKG" . )
echo "[OK] package: $PKG"

echo "== [2] write manifest =="
python3 - "$RID" "$PKG" "$RUN_DIR" "$MAN" <<'PY'
import sys, json, os, time, hashlib
rid, pkg, run_dir, man = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
def sha256(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for ch in iter(lambda: f.read(1024*1024), b''):
            h.update(ch)
    return h.hexdigest()
m = {
  "ok": True,
  "rid": rid,
  "created_ts": int(time.time()),
  "package_path": pkg,
  "package_sha256": sha256(pkg) if os.path.exists(pkg) else None,
  "run_dir": run_dir,
  "notes": "P1 release package for commercial UI",
  "download_url": f"/api/vsp/release_download?rid={rid}",
  "audit_url": f"/api/vsp/release_audit?rid={rid}"
}
with open(man, "w", encoding="utf-8") as f:
    json.dump(m, f, ensure_ascii=False, indent=2)
print("[OK] manifest:", man)
PY

echo "== [3] restart service (release mw already installed) =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] $SVC active" || { systemctl --no-pager status "$SVC" -n 80 || true; exit 2; }

echo "== [4] verify endpoints =="
curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"download_url=",j.get("download_url"))'
curl -fsS -o /tmp/vsp_release_test.zip "$BASE/api/vsp/release_download?rid=$RID"
echo "[OK] downloaded bytes=$(wc -c </tmp/vsp_release_test.zip) => /tmp/vsp_release_test.zip"
