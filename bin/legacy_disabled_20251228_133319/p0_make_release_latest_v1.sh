#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
REL_DIR="$ROOT/out_ci/releases"
mkdir -p "$REL_DIR"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need tar

TS_NOW="$(date +%Y%m%d_%H%M%S)"

SHA_FULL="$(python3 - <<'PY'
import subprocess, hashlib
from pathlib import Path

root = Path("/home/test/Data/SECURITY_BUNDLE")
ui = root/"ui"

sha = ""
try:
    if (root/".git").exists():
        sha = subprocess.check_output(["git","-C",str(root),"rev-parse","HEAD"], text=True).strip()
except Exception:
    sha = ""

if not sha:
    w = ui/"wsgi_vsp_ui_gateway.py"
    data = w.read_bytes() if w.exists() else b""
    sha = hashlib.sha256(data).hexdigest()

print(sha)
PY
)"
SHA12="${SHA_FULL:0:12}"

PKG="VSP_RELEASE_rel-${TS_NOW}_sha-${SHA12}.tgz"
PKG_PATH="$REL_DIR/$PKG"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

MAN="$TMPD/RELEASE_MANIFEST.json"
python3 - <<PY
import json, time
from pathlib import Path

root = Path("$ROOT")
pkg = "$PKG"
ts = "$TS_NOW"
sha_full = "$SHA_FULL"
sha12 = "$SHA12"

m = {
  "release_ts": ts,                          # file-safe
  "release_ts_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "release_sha": sha_full,
  "release_sha12": sha12,
  "release_pkg": f"out_ci/releases/{pkg}",
  "includes": [
    "ui/wsgi_vsp_ui_gateway.py",
    "ui/vsp_demo_app.py",
    "ui/templates/",
    "ui/static/js/",
    "ui/static/css/"
  ]
}
Path("$MAN").write_text(json.dumps(m, indent=2, ensure_ascii=False), encoding="utf-8")
print("[MANIFEST]", "$MAN")
PY

cd "$ROOT"
tar -czf "$PKG_PATH" \
  "ui/wsgi_vsp_ui_gateway.py" \
  "ui/vsp_demo_app.py" \
  "ui/templates" \
  "ui/static/js" \
  "ui/static/css" \
  -C "$TMPD" "RELEASE_MANIFEST.json"

[ -s "$PKG_PATH" ] || { echo "[ERR] pkg empty: $PKG_PATH"; exit 2; }

SHA256="$(python3 - <<PY
import hashlib
from pathlib import Path
p=Path("$PKG_PATH")
h=hashlib.sha256()
with p.open("rb") as f:
    for ch in iter(lambda:f.read(1024*1024), b""):
        h.update(ch)
print(h.hexdigest())
PY
)"
SIZE="$(python3 - <<PY
from pathlib import Path
print(Path("$PKG_PATH").stat().st_size)
PY
)"

REL_JSON="$REL_DIR/release_latest.json"
python3 - <<PY
import json
from pathlib import Path

j = {
  "release_ts": "$TS_NOW",
  "release_sha": "$SHA_FULL",
  "release_pkg": f"out_ci/releases/$PKG",
  "pkg_sha256": "$SHA256",
  "pkg_size": int("$SIZE"),
  "ok": True
}
Path("$REL_JSON").write_text(json.dumps(j, indent=2, ensure_ascii=False), encoding="utf-8")
print("[WRITE]", "$REL_JSON")
print(json.dumps(j, indent=2, ensure_ascii=False))
PY

echo "[OK] created: $PKG_PATH"
echo "[OK] updated: $REL_JSON"
