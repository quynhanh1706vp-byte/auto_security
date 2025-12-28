#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
UNIT="${GH_RUNNER_UNIT:-gh-runner.service}"
RR="/home/test/actions-runner-vsp"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/ops_stamp/${TS}"
mkdir -p "$OUT"

log(){ echo "$*" | tee -a "$OUT/stamp.log"; }

log "== OPS STAMP v1 TS=$TS =="
log "BASE=$BASE UNIT=$UNIT RR=$RR"

# 1) linger status
if command -v loginctl >/dev/null 2>&1; then
  loginctl show-user "$USER" -p Linger > "$OUT/linger.txt" 2>/dev/null || true
  log "[OK] linger => $(cat "$OUT/linger.txt" 2>/dev/null | tr -d '\r' || true)"
else
  log "[WARN] loginctl missing"
fi

# 2) unit truth
systemctl --user cat "$UNIT" > "$OUT/unit.txt"
systemctl --user --no-pager -l status "$UNIT" > "$OUT/unit_status.txt" || true

# 3) runner tail
journalctl --user -u "$UNIT" -n 120 --no-pager > "$OUT/runner_journal_tail.txt" || true

# 4) runner identity
python3 - <<'PYY' > "$OUT/runner_identity.json"
import json, pathlib
p=pathlib.Path("/home/test/actions-runner-vsp/.runner")
j=json.loads(p.read_text(encoding="utf-8-sig", errors="replace"))
out={"agentName": j.get("agentName"), "agentId": j.get("agentId"), "poolName": j.get("poolName"), "gitHubUrl": j.get("gitHubUrl")}
print(json.dumps(out, ensure_ascii=False, indent=2))
PYY

# 5) UI endpoints
for p in "/api/vsp/healthz" "/api/vsp/healthz_v1" "/healthz" "/vsp5" "/c/dashboard"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 6 "$BASE$p" || true)"
  echo "$p $code" >> "$OUT/ui_endpoints.txt"
done

# 6) summary json
python3 - <<'PYY' > "$OUT/OPS_STAMP.json"
import json, pathlib, re
latest=pathlib.Path("out_ci/ops_stamp").resolve() / sorted(pathlib.Path("out_ci/ops_stamp").iterdir())[-1].name
txt=(latest/"runner_journal_tail.txt").read_text(encoding="utf-8", errors="replace") if (latest/"runner_journal_tail.txt").exists() else ""
out={
  "ts": latest.name,
  "base": "http://127.0.0.1:8910",
  "unit": "gh-runner.service",
  "runner_connected": bool(re.search(r"Connected to GitHub", txt, re.I)),
  "runner_ready": bool(re.search(r"Listening for Jobs", txt, re.I)),
  "evidence_dir": str(latest),
}
print(json.dumps(out, indent=2))
PYY

log "[OK] evidence => $OUT"
ls -lah "$OUT" | tee -a "$OUT/stamp.log" >/dev/null
