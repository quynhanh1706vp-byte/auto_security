#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need sha256sum; need awk; need sed; need grep; need sort; need uniq; need mkdir; need tar
command -v zip >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
OUT_ROOT="out_ci/releases"
OUT="$OUT_ROOT/RELEASE_UI_${TS}"
mkdir -p "$OUT"/{html,api,static,logs,meta}

echo "== [P79] UI Commercial Release Pack =="
echo "[INFO] base=$BASE svc=$SVC out=$OUT"

RID="$(curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" \
  | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid",""))')"
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }
echo "[OK] RID=$RID" | tee "$OUT/meta/RID.txt"

RUN_ID="$(curl -fsS "$BASE/api/vsp/datasource?rid=$RID" \
  | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("run_id",""))' 2>/dev/null || true)"
echo "${RUN_ID:-}" > "$OUT/meta/RUN_ID.txt"

# 0) Save basic meta
{
  echo "base=$BASE"
  echo "rid=$RID"
  echo "run_id=${RUN_ID:-}"
  echo "ts=$TS"
  echo "uname=$(uname -a 2>/dev/null || true)"
  echo "whoami=$(whoami 2>/dev/null || true)"
} > "$OUT/meta/env.txt"

if command -v systemctl >/dev/null 2>&1; then
  (systemctl status "$SVC" --no-pager || true) > "$OUT/logs/systemd_status.txt"
  (systemctl show "$SVC" --no-pager || true) > "$OUT/logs/systemd_show.txt"
fi

# 1) Run audit p75
if [ -x bin/p75_dashboard_commercial_audit_v1.sh ]; then
  (bash bin/p75_dashboard_commercial_audit_v1.sh 2>&1 | tee "$OUT/logs/p75_audit.txt") || true
else
  echo "[WARN] missing bin/p75_dashboard_commercial_audit_v1.sh" | tee "$OUT/logs/p75_audit.txt"
fi

# 2) Fetch key APIs
curl -fsS "$BASE/api/vsp/top_findings_v2?limit=50" > "$OUT/api/top_findings_v2.json"
curl -fsS "$BASE/api/vsp/datasource?rid=$RID" > "$OUT/api/datasource_rid.json"

# 3) Fetch HTML tabs
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  f="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  curl -fsS --connect-timeout 2 --max-time 8 "$BASE$p?rid=$RID" > "$f" || {
    echo "[WARN] fetch failed: $p" | tee -a "$OUT/logs/fetch_warn.txt"
  }
done

# Also fetch /c routes if available
croutes=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${croutes[@]}"; do
  f="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  curl -fsS --connect-timeout 2 --max-time 8 "$BASE$p?rid=$RID" > "$f" || true
done

# 4) Extract static references (JS/CSS) from /vsp5
VSP5_HTML="$OUT/html/__vsp5.html"
[ -s "$VSP5_HTML" ] || VSP5_HTML="$OUT/html/__vsp5_.html"
# Robust: pick the first existing vsp5 file
if [ ! -s "$VSP5_HTML" ]; then
  VSP5_HTML="$(ls -1 "$OUT/html" | grep -E 'vsp5' | head -n 1 || true)"
  VSP5_HTML="${VSP5_HTML:+$OUT/html/$VSP5_HTML}"
fi

refs="$OUT/meta/static_refs.txt"
: > "$refs"
if [ -s "${VSP5_HTML:-}" ]; then
  grep -oE '/static/[^"]+\.(js|css)(\?[^"]*)?' "$VSP5_HTML" | sed 's/[?].*//' | sort -u >> "$refs" || true
fi

# Always include these “contract” files for audit
contract_files=(
  /static/js/vsp_dashboard_main_v1.js
  /static/js/vsp_bundle_tabs5_v1.js
  /static/js/vsp_runtime_error_overlay_v1.js
  /static/js/vsp_dashboard_luxe_v1.js
)
for x in "${contract_files[@]}"; do echo "$x"; done >> "$refs"
sort -u "$refs" -o "$refs"

# 5) Download referenced static assets
while read -r r; do
  [ -n "${r:-}" ] || continue
  outp="$OUT/static${r}"
  mkdir -p "$(dirname "$outp")"
  curl -fsS --connect-timeout 2 --max-time 8 "$BASE$r" > "$outp" || {
    echo "[WARN] static fetch failed: $r" | tee -a "$OUT/logs/static_warn.txt"
  }
done < "$refs"

# 6) Release notes + manifest
cat > "$OUT/RELEASE_NOTES.md" <<MD
# VSP UI Commercial Release

- Time: $TS
- Base: $BASE
- RID: $RID
- RUN_ID: ${RUN_ID:-}

## Included
- HTML snapshots: html/
- API snapshots: api/
- Static contract & referenced assets: static/
- Audit logs: logs/

## Commercial defaults
- P64 overlay hidden by default (debug-only)
- SAFE panel hidden by default (debug-only)
- Dashboard renders via dashboard_main_v1.js loader (P72B)

Open demo:
- $BASE/vsp5?rid=$RID
MD

python3 - <<PY > "$OUT/meta/manifest.json"
import json, os, hashlib, datetime, pathlib
out = pathlib.Path("$OUT")
def sha256(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for b in iter(lambda: f.read(1024*1024), b""):
            h.update(b)
    return h.hexdigest()
items=[]
for p in sorted(out.rglob("*")):
    if p.is_file():
        rel=str(p.relative_to(out))
        items.append({"path":rel,"bytes":p.stat().st_size,"sha256":sha256(p)})
manifest={
  "ts":"$TS",
  "base":"$BASE",
  "rid":"$RID",
  "run_id":"${RUN_ID:-}",
  "files":items,
}
print(json.dumps(manifest, indent=2, sort_keys=True))
PY

# 7) Checksums + packages
( cd "$OUT" && find . -type f -maxdepth 4 -print0 | xargs -0 sha256sum | sort -k2 ) > "$OUT/sha256SUMS.txt"

TAR="$OUT_ROOT/RELEASE_UI_${TS}.tar.gz"
( cd "$OUT_ROOT" && tar -czf "$(basename "$TAR")" "RELEASE_UI_${TS}" )
echo "[OK] tar: $TAR"

if command -v zip >/dev/null 2>&1; then
  ZIP="$OUT_ROOT/RELEASE_UI_${TS}.zip"
  ( cd "$OUT_ROOT" && zip -qr "$(basename "$ZIP")" "RELEASE_UI_${TS}" )
  echo "[OK] zip: $ZIP"
fi

echo "[DONE] Release packed at: $OUT"
echo "Open: $BASE/vsp5?rid=$RID"
