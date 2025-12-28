#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_ROOT="out_ci/releases"
OUT="$OUT_ROOT/RELEASE_UI_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need tar; need sha256sum; need find; need cp; need mkdir
command -v zip >/dev/null 2>&1 && HAS_ZIP=1 || HAS_ZIP=0

log(){ echo "$*" | tee -a "$OUT/pack.log"; }
ok(){ log "[OK] $*"; }

log "== [P476] pack UI release (NO-RUN) =="
log "BASE=$BASE OUT=$OUT"

# Choose what to ship (commercial snapshot)
mkdir -p "$OUT/ui"
cp -a templates            "$OUT/ui/" 2>/dev/null || true
cp -a static               "$OUT/ui/" 2>/dev/null || true
cp -a vsp_demo_app.py      "$OUT/ui/" 2>/dev/null || true
cp -a wsgi_vsp_ui_gateway.py "$OUT/ui/" 2>/dev/null || true

# ship essential ops scripts (keep small)
mkdir -p "$OUT/ui/bin"
for f in \
  bin/vsp_ui_ops_safe_v3.sh \
  bin/p473b_sidebar_frame_all_tabs_v1.sh \
  bin/p474b_global_polish_no_run_v1.sh \
  bin/p475_commercial_gate_no_run_v1.sh \
  bin/p476_pack_ui_release_no_run_v1.sh
do
  [ -f "$f" ] && cp -a "$f" "$OUT/ui/bin/" || true
done

# manifest
python3 - <<'PY' >"$OUT/manifest.json"
import os, json, time
from pathlib import Path

root=Path("/home/test/Data/SECURITY_BUNDLE/ui")
out=Path(os.environ.get("OUT","."))

def stat(p:Path):
  try:
    st=p.stat()
    return {"path": str(p.relative_to(root)), "size": st.st_size, "mtime": int(st.st_mtime)}
  except Exception:
    return {"path": str(p), "missing": True}

ship=[
  root/"vsp_demo_app.py",
  root/"wsgi_vsp_ui_gateway.py",
  root/"static/js/vsp_c_sidebar_v1.js",
]
tabs=["/c/dashboard","/c/runs","/c/data_source","/c/settings","/c/rule_overrides"]
tools=["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"]

manifest={
  "type":"VSP_UI_RELEASE_NO_RUN",
  "created_ts": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
  "base_url": os.environ.get("BASE","http://127.0.0.1:8910"),
  "tabs": tabs,
  "pipeline_tools": tools,
  "files": [stat(p) for p in ship],
  "notes": [
    "Commercial UI shell: sidebar + frame + global polish.",
    "NO-RUN release: Run button/live status deferred."
  ]
}
print(json.dumps(manifest, indent=2))
PY
ok "manifest.json"

# inventory + hashes
( cd "$OUT" && find ui -type f -maxdepth 6 -print | sort ) >"$OUT/filelist.txt"
( cd "$OUT" && sha256sum $(cat filelist.txt) ) >"$OUT/sha256sums.txt" 2>/dev/null || true
ok "filelist.txt + sha256sums.txt"

# archive
tar -czf "$OUT_ROOT/RELEASE_UI_${TS}.tgz" -C "$OUT_ROOT" "RELEASE_UI_${TS}"
ok "tgz => $OUT_ROOT/RELEASE_UI_${TS}.tgz"

if [ "$HAS_ZIP" = "1" ]; then
  ( cd "$OUT_ROOT" && zip -qr "RELEASE_UI_${TS}.zip" "RELEASE_UI_${TS}" )
  ok "zip => $OUT_ROOT/RELEASE_UI_${TS}.zip"
else
  log "[WARN] zip not found; tgz already created"
fi

log "[OK] pack log: $OUT/pack.log"
