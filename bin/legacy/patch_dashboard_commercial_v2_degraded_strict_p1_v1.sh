#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PYF="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

grep -q "/api/vsp/dashboard_commercial_v2" "$PYF" && { echo "[OK] dashboard_commercial_v2 already exists"; exit 0; }

cp -f "$PYF" "$PYF.bak_dashv2_${TS}"
echo "[BACKUP] $PYF.bak_dashv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_DASH_COMMERCIAL_V2_DEGRADED_STRICT_P1_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

addon=r'''
# -------------------- {MARK} --------------------
# v2: DEGRADED only when findings missing/parse fail. gate issues => warnings (not degraded)
@app.get("/api/vsp/dashboard_commercial_v2")
def vsp_dashboard_commercial_v2():
    import os
    rd = request.args.get("run_dir", "").strip()
    rd = _vsp_safe_run_dir(rd) or _vsp_pick_latest_run_dir()
    rd = _vsp_safe_run_dir(rd)
    if not rd:
        return jsonify({"ok":False, "error":"NO_RUN_DIR"}), 404

    files=_vsp_find_report_files(rd)

    sev_counts={"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0,"total":0}
    tools=set()

    degraded=[]   # strict: only critical data missing/bad
    warnings=[]   # non-fatal: gate missing/parse

    # findings (critical)
    fp=files["findings_json"]
    if not os.path.isfile(fp):
        alt=os.path.join(rd, "reports", "findings_unified.json")
        if os.path.isfile(alt): fp=alt
    if os.path.isfile(fp):
        try:
            j=_vsp_read_json(fp)
            items = j.get("items") if isinstance(j, dict) else (j if isinstance(j, list) else [])
            if items is None: items=[]
            for it in items:
                sev=str((it.get("severity") or it.get("sev") or "")).upper()
                if sev in sev_counts:
                    sev_counts[sev]+=1
                    sev_counts["total"]+=1
                t=it.get("tool") or it.get("engine")
                if t: tools.add(str(t))
        except Exception:
            degraded.append("findings_parse")
    else:
        degraded.append("findings_missing")

    # gate (warning only)
    gate={}
    gp=files["gate_json"]
    if os.path.isfile(gp):
        try:
            gate=_vsp_read_json(gp) or {}
        except Exception:
            warnings.append("gate_parse")
    else:
        warnings.append("gate_missing")

    overall = {
        "rid": os.path.basename(rd),
        "run_dir": rd,
        "verdict": gate.get("overall_verdict") or gate.get("verdict") or gate.get("status") or "N/A",
        "severity": sev_counts,
        "degraded": degraded,
        "warnings": warnings,
        "degraded_yes": True if degraded else False,
    }
    return jsonify({
        "ok": True,
        "overall": overall,
        "gate": gate,
        "tools": sorted(list(tools)),
        "source": {"findings": fp if os.path.isfile(fp) else "", "gate": gp if os.path.isfile(gp) else ""},
    })
# ------------------ end {MARK} ------------------
'''.replace("{MARK}", MARK)

m=re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
s2 = (s[:m.start()] + addon + "\n\n" + s[m.start():]) if m else (s + "\n\n" + addon)
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$PYF"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "== self-check dash v2 =="
curl -sS "http://127.0.0.1:8910/api/vsp/dashboard_commercial_v2?ts=$TS" | head -c 240; echo
