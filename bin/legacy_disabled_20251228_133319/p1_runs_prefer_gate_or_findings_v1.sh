#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_prefer_${TS}"
echo "[BACKUP] ${F}.bak_runs_prefer_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_PREFER_GATE_OR_FINDINGS_V1"
if marker in s:
    print("[SKIP] already:", marker)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# --- VSP_P1_RUNS_PREFER_GATE_OR_FINDINGS_V1 ---
# Enrich /api/vsp/runs response with rid_latest_gate / rid_latest_findings and prefer them for rid_latest.
try:
    import os
    from pathlib import Path as _Path
except Exception:
    os = None
    _Path = None

def __vsp__runs_pick_latest_with_files(items, roots):
    if not _Path:
        return None, None
    gate_candidates = [
        "run_gate_summary.json",
        "reports/run_gate_summary.json",
        "run_gate.json",
        "reports/run_gate.json",
    ]
    findings_candidates = [
        "reports/findings_unified.json",
        "findings_unified.json",
    ]
    rid_latest_gate = None
    rid_latest_findings = None

    for it in items:
        if not isinstance(it, dict):
            continue
        rid = it.get("run_id")
        if not rid:
            continue
        run_dir = None
        for r in roots or []:
            if not r:
                continue
            cand = _Path(r) / rid
            if cand.exists():
                run_dir = cand
                break
        if not run_dir:
            continue

        # gate?
        if rid_latest_gate is None:
            for rel in gate_candidates:
                if (run_dir / rel).exists():
                    rid_latest_gate = rid
                    break

        # findings?
        if rid_latest_findings is None:
            for rel in findings_candidates:
                if (run_dir / rel).exists():
                    rid_latest_findings = rid
                    break

        if rid_latest_gate and rid_latest_findings:
            break

    return rid_latest_gate, rid_latest_findings

# Hook: wrap existing runs handler at WSGI layer if payload builder exists.
try:
    __vsp__runs_payload_prev = __vsp__runs_payload  # type: ignore[name-defined]
    def __vsp__runs_payload(*args, **kwargs):  # noqa: F811
        data = __vsp__runs_payload_prev(*args, **kwargs)
        try:
            if isinstance(data, dict) and isinstance(data.get("items"), list):
                roots = data.get("roots_used") or []
                rid_latest_gate, rid_latest_findings = __vsp__runs_pick_latest_with_files(data["items"], roots)
                data["rid_latest_gate"] = rid_latest_gate
                data["rid_latest_findings"] = rid_latest_findings
                # prefer stable latest
                data["rid_latest"] = rid_latest_gate or rid_latest_findings or data.get("rid_latest")
        except Exception:
            pass
        return data
except Exception:
    pass
""").strip() + "\n"

p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
print("[OK] appended:", marker)
PY

python3 -m py_compile "$F"
sudo systemctl restart vsp-ui-8910.service

BASE=http://127.0.0.1:8910
curl -sS "$BASE/api/vsp/runs?limit=2" | head -c 1200; echo
