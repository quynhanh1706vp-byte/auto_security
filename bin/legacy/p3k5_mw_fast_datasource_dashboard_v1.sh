#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

MOD="vsp_dash_fallback_mw_p3k2.py"
[ -f "$MOD" ] || { echo "[ERR] missing $MOD (p3k2 module)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$MOD" "${MOD}.bak_p3k5_${TS}"
echo "[BACKUP] ${MOD}.bak_p3k5_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("vsp_dash_fallback_mw_p3k2.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P3K5_DATASOURCE_FAST_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert block before findings_effective handler (stable anchor from P3K3)
anchor = r"# --- findings_effective_v1/<rid>\?limit=0 ---"
m = re.search(anchor, s)
if not m:
    # fallback: insert before findings_page_v3
    anchor2 = r"# --- findings_page_v3"
    m = re.search(anchor2, s)
    if not m:
        raise SystemExit("[ERR] cannot find insertion anchor in module")

ins = f"""
        # {MARK}
        # --- datasource (dashboard) : force ok + lite findings to avoid watchdog/timeouts ---
        if path in ("/api/vsp/datasource", "/api/vsp/datasource_lite"):
            b = _base(rid)
            # conservative limits (UI only needs small slice for dashboard)
            limit = int((qs.get("limit") or ["200"])[0] or 200)
            offset = int((qs.get("offset") or ["0"])[0] or 0)
            limit = max(1, min(limit, 500))
            findings = b["items"][offset:offset+limit]
            runs = b["runs_index"][:40]
            payload = {{
                "ok": True,
                "rid": rid,
                "run_id": rid,
                "mode": (qs.get("mode") or [""])[0] or None,
                "lite": True,
                "total": b["total"],
                "runs": runs,
                "findings": findings,
                "returned": len(findings),
                "kpis": {{
                    "total": b["total"],
                    "CRITICAL": b["sev"].get("CRITICAL", 0),
                    "HIGH": b["sev"].get("HIGH", 0),
                    "MEDIUM": b["sev"].get("MEDIUM", 0),
                    "LOW": b["sev"].get("LOW", 0),
                    "INFO": b["sev"].get("INFO", 0),
                    "TRACE": b["sev"].get("TRACE", 0),
                }},
            }}
            return self._json(start_response, payload)

"""

s2 = s[:m.start()] + ins + s[m.start():]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted datasource fast handler")
PY

echo "== import check =="
"$PY" -c "import vsp_dash_fallback_mw_p3k2; print('MOD_IMPORT_OK')" >/dev/null

echo "== restart =="
sudo systemctl restart "$SVC"
sleep 0.7
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 3
}

echo "[DONE] p3k5_mw_fast_datasource_dashboard_v1"
