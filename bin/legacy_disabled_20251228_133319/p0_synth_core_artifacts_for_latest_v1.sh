#!/usr/bin/env bash
set -euo pipefail
UI="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$UI"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
RUN_DIR="$(curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("run_dir") or "")')"
echo "[RID]=$RID"
echo "[RUN_DIR]=$RUN_DIR"
[ -n "$RUN_DIR" ] || { echo "[ERR] cannot resolve run_dir"; exit 2; }

python3 - <<PY
from pathlib import Path
import json, time, os

rid = "${RID}"
run_dir = Path("${RUN_DIR}")
reports = run_dir/"reports"
evidence = run_dir/"evidence"
reports.mkdir(exist_ok=True)
evidence.mkdir(exist_ok=True)

def load_findings():
    fu = run_dir/"findings_unified.json"
    if fu.is_file():
        try:
            j=json.loads(fu.read_text(encoding="utf-8", errors="replace"))
            if isinstance(j, dict) and isinstance(j.get("findings"), list):
                return j["findings"]
            if isinstance(j, list):
                return j
        except Exception:
            pass
    return []

def sev_counts(findings):
    lvls=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
    c={k:0 for k in lvls}
    for x in findings:
        if not isinstance(x, dict): 
            continue
        s=(x.get("severity") or x.get("sev") or "INFO").upper().strip()
        if s not in c: s="INFO"
        c[s]+=1
    return c

# SUMMARY.txt
summary = run_dir/"SUMMARY.txt"
if not summary.is_file():
    f=load_findings()
    c=sev_counts(f)
    txt = []
    txt.append(f"VSP SUMMARY (synth)\nRID={rid}\nTS={time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    txt.append("COUNTS_BY_SEVERITY:")
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        txt.append(f"  {k}: {c.get(k,0)}")
    txt.append("")
    summary.write_text("\n".join(txt), encoding="utf-8")

# run_manifest.json
rm = run_dir/"run_manifest.json"
if not rm.is_file():
    # list a bounded set
    items=[]
    for root, _dirs, files in os.walk(run_dir):
        # prune huge
        if "/.git/" in root or "/node_modules/" in root or "/__pycache__/" in root:
            continue
        for fn in files:
            p=Path(root)/fn
            rel=str(p.relative_to(run_dir))
            try:
                items.append({"path": rel, "bytes": p.stat().st_size})
            except Exception:
                items.append({"path": rel, "bytes": None})
        if len(items) > 8000:
            break
    rm.write_text(json.dumps({
        "ok": True,
        "rid": rid,
        "run_dir": str(run_dir),
        "generated_by": "core_artifacts_synth_v1",
        "ts": int(time.time()),
        "files_count": len(items),
        "files": items[:8000],
    }, ensure_ascii=False, indent=2), encoding="utf-8")

# run_evidence_index.json
rei = run_dir/"run_evidence_index.json"
if not rei.is_file():
    prefer = [
        "evidence/ui_engine.log",
        "evidence/trace.zip",
        "evidence/last_page.html",
        "reports/findings_unified.html",
        "reports/findings_unified.pdf",
        "reports/findings_unified.csv",
        "reports/findings_unified.sarif",
        "run_gate.json",
        "run_gate_summary.json",
        "SUMMARY.txt",
    ]
    idx=[]
    for rel in prefer:
        p=run_dir/rel
        idx.append({
            "path": rel,
            "exists": p.is_file(),
            "bytes": (p.stat().st_size if p.is_file() else 0),
        })
    rei.write_text(json.dumps({
        "ok": True,
        "rid": rid,
        "generated_by": "core_artifacts_synth_v1",
        "ts": int(time.time()),
        "index": idx
    }, ensure_ascii=False, indent=2), encoding="utf-8")

# run_gate_summary.json (stub if missing)
rgs = run_dir/"run_gate_summary.json"
if not rgs.is_file():
    rgs.write_text(json.dumps({
        "ok": True,
        "rid": rid,
        "overall": "DEGRADED",
        "note": "synth stub: real gate summary missing",
        "generated_by": "core_artifacts_synth_v1",
        "ts": int(time.time()),
    }, ensure_ascii=False, indent=2), encoding="utf-8")

# run_gate.json (stub if missing)
rg = run_dir/"run_gate.json"
if not rg.is_file():
    rg.write_text(json.dumps({
        "ok": True,
        "rid": rid,
        "overall_status": "DEGRADED",
        "by_type": {},
        "note": "synth stub: real run_gate.json missing",
        "generated_by": "core_artifacts_synth_v1",
        "ts": int(time.time()),
    }, ensure_ascii=False, indent=2), encoding="utf-8")

print("[OK] core artifacts synth done")
PY

echo "== re-check manifest (lite) =="
curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"))'
