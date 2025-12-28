#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node; need sha256sum; need tar; need gzip; need curl
command -v zip >/dev/null 2>&1 && HAS_ZIP=1 || HAS_ZIP=0
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

OUTDIR="releases"
mkdir -p "$OUTDIR"

TS="$(date +%Y%m%d_%H%M%S)"
REL="VSP_UI_COMMERCIAL_${TS}"
STAGE="/tmp/${REL}"
export REL STAGE BASE OUTDIR

rm -rf "$STAGE"
mkdir -p "$STAGE/ui"

echo "== [0] sanity compile (no surprises) =="
python3 -m py_compile vsp_demo_app.py wsgi_vsp_ui_gateway.py
node --check static/js/vsp_dash_only_v1.js >/dev/null
echo "[OK] compile ok"

echo "== [1] stage files =="
cp -a vsp_demo_app.py wsgi_vsp_ui_gateway.py "$STAGE/ui/"
cp -a templates static "$STAGE/ui/"
mkdir -p "$STAGE/ui/bin"
cp -a bin/p0_commercial_clean_pack_v1b_fix_selfcheck.sh "$STAGE/ui/bin/" 2>/dev/null || true
echo "[OK] staged to $STAGE/ui"

echo "== [2] write manifest (in stage) =="
python3 - <<'PY'
import json, os, subprocess, time, pathlib
root = pathlib.Path(os.environ["STAGE"]) / "ui"

def git_rev():
    try:
        r = subprocess.check_output(
            ["git","rev-parse","--short","HEAD"],
            cwd="/home/test/Data/SECURITY_BUNDLE/ui",
            stderr=subprocess.DEVNULL
        ).decode().strip()
        return r
    except Exception:
        return None

m = {
  "ok": True,
  "name": os.environ.get("REL"),
  "ts": int(time.time()),
  "git": git_rev(),
  "files": []
}
for p in sorted(root.rglob("*")):
    if p.is_file():
        m["files"].append(str(p.relative_to(root)))
(root/"release_manifest.json").write_text(json.dumps(m, indent=2), encoding="utf-8")
print("[OK] wrote", root/"release_manifest.json")
PY

echo "== [3] build package =="
if [ "$HAS_ZIP" -eq 1 ]; then
  PKG="${OUTDIR}/${REL}.zip"
  (cd "$STAGE" && zip -qr "/home/test/Data/SECURITY_BUNDLE/ui/${PKG}" .)
else
  PKG="${OUTDIR}/${REL}.tar.gz"
  (cd "$STAGE" && tar -cf - . | gzip -9 > "/home/test/Data/SECURITY_BUNDLE/ui/${PKG}")
fi
echo "[OK] package: $PKG"

echo "== [4] sha256 =="
SHA="$(sha256sum "$PKG" | awk '{print $1}')"
echo "$SHA  $(basename "$PKG")" > "${PKG}.sha256"
echo "[OK] sha256: $SHA"

echo "== [5] write releases/release_latest.json (local file) =="
python3 - <<PY
import json, time
obj = {
  "ok": True,
  "name": "${REL}",
  "package_path": "${PKG}",
  "sha256": "${SHA}",
  "ts": int(time.time()),
  "base": "${BASE}"
}
open("${OUTDIR}/release_latest.json","w",encoding="utf-8").write(json.dumps(obj, indent=2))
print("[OK] wrote ${OUTDIR}/release_latest.json")
PY

echo "== [6] quick smoke (API still OK) =="
curl -fsS -I "$BASE/api/vsp/rid_latest_gate_root" | grep -i 'X-VSP-RIDPICK:' || true
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("rid",""))')"
[ -n "$RID" ] || { echo "[ERR] empty rid from rid_latest_gate_root"; exit 2; }
curl -fsS "$BASE/api/vsp/top_findings_v4?rid=$RID&limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); assert j.get("ok"); assert len(j.get("items") or [])>=1; print("[OK] top_findings_v4 returns items")'

echo
echo "== [DONE] Release packed =="
echo "PKG:  $PKG"
echo "SHA:  $SHA"
echo "META: ${OUTDIR}/release_latest.json"
