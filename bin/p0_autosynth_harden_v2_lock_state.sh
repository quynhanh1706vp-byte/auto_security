#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need systemctl; need date
command -v sudo >/dev/null 2>&1 || { echo "[ERR] missing sudo"; exit 2; }

BIN="/home/test/Data/SECURITY_BUNDLE/ui/bin"
W="$BIN/vsp_autosynth_worker_v1.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_${TS}"
echo "[BACKUP] ${W}.bak_${TS}"

echo "== [1] rewrite worker with state + bounded scan =="
cat > "$W" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import json, time, os, subprocess, sys

UI = Path("/home/test/Data/SECURITY_BUNDLE/ui")
SYNTH = UI / "bin" / "vsp_report_synth_v1.py"
STATE = UI / "out_ci" / "autosynth_state_v2.json"
STATE.parent.mkdir(parents=True, exist_ok=True)

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

# tuning knobs (commercial-safe)
SCAN_PER_ROOT = 120          # only newest N dirs per root
MAX_AGE_DAYS   = 30          # ignore very old runs
STATE_KEEP_MAX = 4000        # cap memory growth

def _load_state():
    try:
        if STATE.is_file():
            return json.loads(STATE.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        pass
    return {"done": {}, "ts": int(time.time())}

def _save_state(st):
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    tmp.replace(STATE)

def missing_any(run_dir: Path) -> list[str]:
    miss=[]
    for rel in REQUIRED:
        if not (run_dir/rel).is_file():
            miss.append(rel)
    return miss

def ensure_core(run_dir: Path, rid: str):
    import time as _t
    # SUMMARY.txt
    p = run_dir/"SUMMARY.txt"
    if not p.is_file():
        p.write_text(f"VSP SUMMARY (autosynth)\nRID={rid}\nTS={_t.strftime('%Y-%m-%d %H:%M:%S')}\n", encoding="utf-8")

    # run_gate_summary.json stub
    p = run_dir/"run_gate_summary.json"
    if not p.is_file():
        p.write_text(json.dumps({"ok": True,"rid": rid,"overall":"DEGRADED","note":"autosynth stub"}, ensure_ascii=False, indent=2), encoding="utf-8")

    # run_gate.json stub
    p = run_dir/"run_gate.json"
    if not p.is_file():
        p.write_text(json.dumps({"ok": True,"rid": rid,"overall_status":"DEGRADED","note":"autosynth stub"}, ensure_ascii=False, indent=2), encoding="utf-8")

    # run_manifest.json (bounded)
    p = run_dir/"run_manifest.json"
    if not p.is_file():
        files=[]
        cap=6000
        for root, _dirs, fnames in os.walk(run_dir):
            if "/.git/" in root or "/node_modules/" in root or "/__pycache__/" in root:
                continue
            for fn in fnames:
                fp = Path(root)/fn
                rel = str(fp.relative_to(run_dir))
                try:
                    files.append({"path": rel, "bytes": fp.stat().st_size})
                except Exception:
                    files.append({"path": rel, "bytes": None})
                if len(files) >= cap:
                    break
            if len(files) >= cap:
                break
        p.write_text(json.dumps({"ok": True,"rid": rid,"ts": int(_t.time()),"files_count": len(files),"files": files},
                                ensure_ascii=False, indent=2), encoding="utf-8")

    # run_evidence_index.json
    p = run_dir/"run_evidence_index.json"
    if not p.is_file():
        prefer = ["evidence/ui_engine.log","evidence/trace.zip","evidence/last_page.html",
                  "reports/findings_unified.html","reports/findings_unified.pdf","reports/findings_unified.csv","reports/findings_unified.sarif",
                  "run_gate.json","run_gate_summary.json","SUMMARY.txt"]
        idx=[]
        for rel in prefer:
            fp = run_dir/rel
            idx.append({"path": rel, "exists": fp.is_file(), "bytes": (fp.stat().st_size if fp.is_file() else 0)})
        p.write_text(json.dumps({"ok": True,"rid": rid,"ts": int(_t.time()),"index": idx}, ensure_ascii=False, indent=2), encoding="utf-8")

def is_too_old(p: Path) -> bool:
    try:
        age = (time.time() - p.stat().st_mtime) / 86400.0
        return age > MAX_AGE_DAYS
    except Exception:
        return False

def main():
    if not SYNTH.is_file():
        print(json.dumps({"ok": False, "err": f"missing synth {SYNTH}"}, ensure_ascii=False))
        return 2

    st = _load_state()
    done = st.get("done") or {}
    fixed = 0
    checked = 0
    now = int(time.time())

    for root in ROOTS:
        if not root.is_dir():
            continue
        dirs = [d for d in root.iterdir() if d.is_dir()]
        dirs.sort(key=lambda p: p.stat().st_mtime, reverse=True)

        for d in dirs[:SCAN_PER_ROOT]:
            rid = d.name
            if is_too_old(d):
                continue

            checked += 1
            miss = missing_any(d)
            if not miss:
                done[rid] = {"ts": now, "ok": True}
                continue

            # If we already fixed recently and still missing, don't hammer every minute
            prev = done.get(rid) or {}
            if prev.get("ok") is True and (now - int(prev.get("ts") or 0)) < 3600:
                continue

            # 1) try reports synth (csv/sarif/html/pdf)
            try:
                subprocess.check_call([sys.executable, str(SYNTH), "--run-dir", str(d), "--title", f"VSP Findings Report • {rid}"],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass

            # 2) ensure core
            try:
                ensure_core(d, rid)
            except Exception:
                pass

            miss2 = missing_any(d)
            if not miss2:
                fixed += 1
                done[rid] = {"ts": now, "ok": True}
            else:
                done[rid] = {"ts": now, "ok": False, "missing": miss2[:12]}

    # prune state
    if len(done) > STATE_KEEP_MAX:
        # keep newest
        items = sorted(done.items(), key=lambda kv: int((kv[1] or {}).get("ts") or 0), reverse=True)[:STATE_KEEP_MAX]
        done = dict(items)

    st["done"] = done
    st["ts"] = now
    _save_state(st)

    print(json.dumps({"ok": True, "fixed_runs": fixed, "checked": checked, "state": str(STATE), "ts": now}, ensure_ascii=False))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
PY

python3 -m py_compile "$W"
echo "[OK] worker py_compile passed"

echo "== [2] harden systemd service: flock + timeout =="
sudo tee /etc/systemd/system/vsp-autosynth.service >/dev/null <<EOF
[Unit]
Description=VSP AutoSynth (Reports + Core Artifacts)
After=network.target

[Service]
Type=oneshot
User=test
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
TimeoutStartSec=300
ExecStart=/usr/bin/flock -n /tmp/vsp-autosynth.lock /usr/bin/python3 /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_autosynth_worker_v1.py
EOF

echo "== [3] tune timer: 2 minutes + jitter + persistent =="
sudo tee /etc/systemd/system/vsp-autosynth.timer >/dev/null <<'EOF'
[Unit]
Description=Run VSP AutoSynth every 2 minutes (commercial hardened)

[Timer]
OnBootSec=25s
OnUnitActiveSec=120s
RandomizedDelaySec=15s
Persistent=true
Unit=vsp-autosynth.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl restart vsp-autosynth.timer

echo "== [4] run once now =="
sudo systemctl start vsp-autosynth.service || true
journalctl -u vsp-autosynth.service -n 25 --no-pager || true

echo "[DONE] AutoSynth hardened v2."
