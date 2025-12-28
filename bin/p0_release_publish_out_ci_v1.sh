#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need python3; need date; need mkdir; need cp; need ls; need sha256sum

# 0) run full gate+pack to generate fresh package
bash bin/p0_release_and_gate_one_shot_v1.sh | tee /tmp/vsp_ui_release_publish_last.log

# 1) locate latest package from log
PKG="$(grep -oE 'out_release/UI_COMMERCIAL_[0-9]{8}_[0-9]{6}\.tgz' /tmp/vsp_ui_release_publish_last.log | tail -n1 || true)"
[ -n "${PKG:-}" ] || { echo "[ERR] cannot detect PKG from log"; exit 2; }

SHA="${PKG%.tgz}.sha256"
MAN="${PKG%.tgz}.manifest.txt"

# 2) publish into out_ci/releases
PUB="out_ci/releases"
mkdir -p "$PUB"
cp -f "$PKG" "$SHA" "$MAN" "$PUB/"

# 3) write release_latest.json
python3 - <<PY
import json, os, time
pkg = "$PUB/$(basename "$PKG")"
sha = "$PUB/$(basename "$SHA")"
man = "$PUB/$(basename "$MAN")"
j = {
  "ok": True,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "package": pkg,
  "sha256_file": sha,
  "manifest": man,
}
open("out_ci/release_latest.json","w",encoding="utf-8").write(json.dumps(j, ensure_ascii=False, indent=2))
print("[OK] wrote out_ci/release_latest.json")
PY

echo "== published =="
ls -lh "$PUB/$(basename "$PKG")" "$PUB/$(basename "$SHA")" "$PUB/$(basename "$MAN")" out_ci/release_latest.json
echo
echo "[OK] Current Release: $PUB/$(basename "$PKG")"
