#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
ERRLOG="${VSP_UI_ERRLOG:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need head; need tail; need date; need python3; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.pre_rescue_${TS}"
echo "[OK] saved current as ${W}.pre_rescue_${TS}"

# Prefer specific backups first (likely stable)
cands=()
while IFS= read -r f; do cands+=("$f"); done < <(ls -1t \
  ${W}.bak_topfind_* \
  ${W}.bak_append_* \
  ${W}.bak_* 2>/dev/null | head -n 40)

if [ "${#cands[@]}" -eq 0 ]; then
  echo "[ERR] no backups found for $W"
  exit 2
fi

echo "== candidates =="
printf "%s\n" "${cands[@]}" | sed 's/^/ - /'

probe_topfind(){
  local http ctype
  http="$(curl -sS -o /tmp/topfind_probe.json -w '%{http_code}' "$BASE/api/vsp/top_findings_v1?limit=1" || true)"
  ctype="$(curl -sSI "$BASE/api/vsp/top_findings_v1?limit=1" | awk -F': ' 'tolower($1)=="content-type"{print $2}' | tr -d '\r' | tail -n 1 || true)"
  if [ "$http" != "200" ]; then
    echo "[PROBE] http=$http ctype=${ctype:-?}"
    return 1
  fi
  if echo "${ctype:-}" | grep -qi 'application/json'; then
    if python3 - <<'PY' >/dev/null 2>&1
import json
j=json.load(open("/tmp/topfind_probe.json","r",encoding="utf-8"))
assert j.get("ok") in (True, "true", 1)
PY
    then
      echo "[PROBE] http=200 ctype=json ok=true"
      return 0
    fi
  fi
  echo "[PROBE] http=200 but not json/ok (ctype=${ctype:-?})"
  return 1
}

for b in "${cands[@]}"; do
  echo "== try restore from $b =="
  cp -f "$b" "$W" || { echo "[WARN] cannot copy $b"; continue; }

  if ! python3 -m py_compile "$W" >/dev/null 2>&1; then
    echo "[WARN] py_compile fail for $b"
    continue
  fi

  sudo systemctl restart "$SVC" || true
  if ! sudo systemctl is-active --quiet "$SVC"; then
    echo "[WARN] service not active with $b"
    continue
  fi

  if probe_topfind; then
    echo "[OK] FOUND GOOD WSGI: $b"
    echo "[OK] keeping restored $W"
    exit 0
  else
    echo "[WARN] top_findings still broken on $b"
    if [ -f "$ERRLOG" ]; then
      echo "---- errlog tail ----"
      tail -n 30 "$ERRLOG" | sed 's/^/[ERRLOG] /'
      echo "---------------------"
    fi
  fi
done

echo "[ERR] cannot find a backup that makes top_findings healthy"
echo "[INFO] restoring original pre_rescue"
cp -f "${W}.pre_rescue_${TS}" "$W"
sudo systemctl restart "$SVC" || true
exit 2
