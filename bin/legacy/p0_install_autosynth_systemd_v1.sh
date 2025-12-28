#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need systemctl; need date

UI="/home/test/Data/SECURITY_BUNDLE/ui"
OUT1="/home/test/Data/SECURITY-10-10-v4/out_ci"
OUT2="/home/test/Data/SECURITY_BUNDLE/out_ci"
BIN="$UI/bin"

# 1) worker script
cat > "$BIN/vsp_autosynth_worker_v1.py" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import json, time, os, subprocess, sys

UI = Path("/home/test/Data/SECURITY_BUNDLE/ui")
SYNTH = UI/"bin"/"vsp_report_synth_v1.py"

ROOTS = [
    Path("/home/test/Data/SECURITY-10-10-v4/out_ci"),
    Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
]

REQUIRED = [
    "SUMMARY.txt",
    "run_manifest.json",
    "run_evidence_index.json",
    "run_gate.json",
    "run_gate_summary.json",
    "reports/findings_unified.csv",
    "reports/findings_unified.sarif",
    "reports/findings_unified.html",
    "reports/findings_unified.pdf",
]

def ensure_core(run_dir: Path, rid: str):
    # Minimal core synth: only create missing required non-report files.
    import json, time, os
    from pathlib import Path as P

    def mk_summary():
        p = run_dir/"SUMMARY.txt"
        if p.is_file(): return
        p.write_text(f"VSP SUMMARY (autosynth)\nRID={rid}\nTS={time.strftime('%Y-%m-%d %H:%M:%S')}\n", encoding="utf-8")

    def mk_manifest():
        p = run_dir/"run_manifest.json"
        if p.is_file(): return
        files=[]
        for root, _dirs, fnames in os.walk(run_dir):
            if "/.git/" in root or "/node_modules/" in root or "/__pycache__/" in root:
                continue
            for fn in fnames:
                fp = P(root)/fn
                rel = str(fp.relative_to(run_dir))
                try:
                    files.append({"path": rel, "bytes": fp.stat().st_size})
                except Exception:
                    files.append({"path": rel, "bytes": None})
            if len(files) > 8000:
                break
        p.write_text(json.dumps({"ok": True,"rid": rid,"ts": int(time.time()),"files_count": len(files),"files": files[:8000]},
                                ensure_ascii=False, indent=2), encoding="utf-8")

    def mk_index():
        p = run_dir/"run_evidence_index.json"
        if p.is_file(): return
        prefer = ["evidence/ui_engine.log","evidence/trace.zip","evidence/last_page.html",
                  "reports/findings_unified.html","reports/findings_unified.pdf","reports/findings_unified.csv","reports/findings_unified.sarif",
                  "run_gate.json","run_gate_summary.json","SUMMARY.txt"]
        idx=[]
        for rel in prefer:
            fp = run_dir/rel
            idx.append({"path": rel, "exists": fp.is_file(), "bytes": (fp.stat().st_size if fp.is_file() else 0)})
        p.write_text(json.dumps({"ok": True,"rid": rid,"ts": int(time.time()),"index": idx}, ensure_ascii=False, indent=2), encoding="utf-8")

    def mk_gate_stub():
        p = run_dir/"run_gate.json"
        if p.is_file(): return
        p.write_text(json.dumps({"ok": True,"rid": rid,"overall_status":"DEGRADED","note":"autosynth stub"},
                                ensure_ascii=False, indent=2), encoding="utf-8")

    def mk_gate_summary_stub():
        p = run_dir/"run_gate_summary.json"
        if p.is_file(): return
        p.write_text(json.dumps({"ok": True,"rid": rid,"overall":"DEGRADED","note":"autosynth stub"},
                                ensure_ascii=False, indent=2), encoding="utf-8")

    mk_summary(); mk_manifest(); mk_index(); mk_gate_stub(); mk_gate_summary_stub()

def missing_any(run_dir: Path) -> list[str]:
    miss=[]
    for rel in REQUIRED:
        if not (run_dir/rel).is_file():
            miss.append(rel)
    return miss

def main():
    if not SYNTH.is_file():
        print("[ERR] missing synth:", SYNTH)
        return 2

    fixed=0
    for root in ROOTS:
        if not root.is_dir():
            continue
        # only scan plausible run dirs
        for d in sorted(root.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)[:250]:
            if not d.is_dir():
                continue
            rid = d.name
            miss = missing_any(d)
            if not miss:
                continue

            # Create reports first (csv/sarif/html/pdf)
            try:
                subprocess.check_call([sys.executable, str(SYNTH), "--run-dir", str(d), "--title", f"VSP Findings Report • {rid}"],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass

            # Ensure core files
            try:
                ensure_core(d, rid)
            except Exception:
                pass

            miss2 = missing_any(d)
            if not miss2:
                fixed += 1

    print(json.dumps({"ok": True, "fixed_runs": fixed, "ts": int(time.time())}, ensure_ascii=False))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
PY
chmod +x "$BIN/vsp_autosynth_worker_v1.py"
python3 -m py_compile "$BIN/vsp_autosynth_worker_v1.py"

# 2) systemd service + timer
sudo tee /etc/systemd/system/vsp-autosynth.service >/dev/null <<EOF
[Unit]
Description=VSP AutoSynth (Reports + Core Artifacts)
After=network.target

[Service]
Type=oneshot
User=test
WorkingDirectory=$UI
ExecStart=/usr/bin/python3 $BIN/vsp_autosynth_worker_v1.py
EOF

sudo tee /etc/systemd/system/vsp-autosynth.timer >/dev/null <<'EOF'
[Unit]
Description=Run VSP AutoSynth every 60s

[Timer]
OnBootSec=20s
OnUnitActiveSec=60s
Unit=vsp-autosynth.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now vsp-autosynth.timer

echo "== status timer =="
systemctl status vsp-autosynth.timer --no-pager | sed -n '1,20p' || true
echo
echo "== run once now =="
systemctl start vsp-autosynth.service || true
journalctl -u vsp-autosynth.service -n 30 --no-pager || true

echo "[DONE] AutoSynth installed."
