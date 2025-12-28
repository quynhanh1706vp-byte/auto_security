#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/COMMERCE_LOCK_${TS}"
PKG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/COMMERCE_LOCK_${TS}.tgz"

mkdir -p "$OUT"/{html,probes,systemd,notes}

echo "[INFO] OUT=$OUT"
echo "[INFO] PKG=$PKG"
echo "[INFO] BASE=$BASE RID=$RID SVC=$SVC"

# ---- Tabs HTML (5 tabs) ----
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  f="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  echo "[FETCH] $p"
  curl -fsS --connect-timeout 2 --max-time 10 --range 0-240000 "$BASE$p?rid=$RID" -o "$f" \
    || echo "[WARN] fetch failed: $p" >> "$OUT/probes/_warn.txt"
done

# ---- API probes: save body + headers + code ----
probe(){
  local name="$1"; shift
  local url="$1"; shift
  echo "[PROBE] $name"
  curl -sS -D "$OUT/probes/${name}.hdr" -o "$OUT/probes/${name}.body" -w "%{http_code}\n" \
    --connect-timeout 2 --max-time 25 "$url" > "$OUT/probes/${name}.code" || true
  echo "[INFO] $(cat "$OUT/probes/${name}.code" | tr -d '\n') $url" >> "$OUT/probes/_meta.txt"
}

probe "findings_page_v3" "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
probe "top_findings_v3c" "$BASE/api/vsp/top_findings_v3c?rid=$RID&limit=200"
probe "trend_v1"        "$BASE/api/vsp/trend_v1"
probe "runs"            "$BASE/api/vsp/runs?limit=5&offset=0"

# ---- systemd + logs ----
(systemctl is-active "$SVC" || true) > "$OUT/systemd/is_active.txt" 2>&1
(systemctl --no-pager --full status "$SVC" | sed -n '1,70p' || true) > "$OUT/systemd/status.txt" 2>&1
(systemctl cat "$SVC" || true) > "$OUT/systemd/unit_and_dropins.txt" 2>&1
(sudo journalctl -u "$SVC" -n 120 --no-pager || true) > "$OUT/systemd/journal_tail.txt" 2>&1

# ---- proofnote ----
FP="$(grep -aoE '"from_path"\s*:\s*"[^"]+"' "$OUT/probes/findings_page_v3.body" | head -n 1 | sed 's/^"from_path"\s*:\s*"//; s/"$//')"
TF="$(grep -aoE '"total_findings"\s*:\s*[0-9]+' "$OUT/probes/findings_page_v3.body" | head -n 1 | sed 's/.*:\s*//')"
cat > "$OUT/notes/PROOFNOTE.txt" <<EOF
VSP COMMERCE LOCK (MIN PACK)
TS: $TS
BASE: $BASE
RID(open): $RID

findings_page_v3:
- from_path: ${FP:-"(see probes/findings_page_v3.body)"}
- total_findings: ${TF:-"(see probes/findings_page_v3.body)"}

Artifacts:
- html/*.html
- probes/*.body/*.hdr/*.code
- systemd/*
EOF

# ---- pack ----
tar -czf "$PKG" -C "$(dirname "$OUT")" "$(basename "$OUT")"
ln -sf "$PKG" /home/test/Data/SECURITY_BUNDLE/ui/out_ci/COMMERCE_LOCK_LATEST.tgz

echo "[OK] PACKED: $PKG"
echo "[OK] LATEST: /home/test/Data/SECURITY_BUNDLE/ui/out_ci/COMMERCE_LOCK_LATEST.tgz"
