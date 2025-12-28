#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixb_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need ls; need head; need grep; need curl
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl" | tee -a "$OUT/log.txt"; exit 2; }

ok(){ echo "[OK] $*" | tee -a "$OUT/log.txt"; }
warn(){ echo "[WARN] $*" | tee -a "$OUT/log.txt"; }
err(){ echo "[ERR] $*" | tee -a "$OUT/log.txt"; exit 2; }

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || err "missing $W"

echo "== [0] capture status/journal (before) ==" | tee -a "$OUT/log.txt"
sudo systemctl status "$SVC" --no-pager > "$OUT/status_before.txt" 2>&1 || true
sudo journalctl -u "$SVC" -n 200 --no-pager > "$OUT/journal_before.txt" 2>&1 || true

echo "== [1] rollback WSGI to last known good backup from p463fix_* ==" | tee -a "$OUT/log.txt"
last_fix="$(ls -1dt out_ci/p463fix_* 2>/dev/null | head -n1 || true)"
[ -n "$last_fix" ] || err "cannot find out_ci/p463fix_* dir"
bak="$(ls -1t "$last_fix/${W}.bak_"* 2>/dev/null | head -n1 || true)"
[ -n "$bak" ] || err "cannot find backup $W in $last_fix"
cp -f "$bak" "$W"
ok "restored $W <= $bak"
python3 -m py_compile "$W" | tee -a "$OUT/log.txt"
ok "py_compile $W PASS (after rollback)"

echo "== [2] restart service (should come back) ==" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

# quick wait up to 30s for port
up=0
for i in $(seq 1 15); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" -o /dev/null; then up=1; break; fi
  sleep 2
done

if [ "$up" -ne 1 ]; then
  warn "UI still not reachable after rollback+restart"
  sudo systemctl status "$SVC" --no-pager > "$OUT/status_after_rollback.txt" 2>&1 || true
  sudo journalctl -u "$SVC" -n 200 --no-pager > "$OUT/journal_after_rollback.txt" 2>&1 || true
  err "stop here: service not up. See $OUT/status_after_rollback.txt and $OUT/journal_after_rollback.txt"
fi
ok "UI reachable again: $BASE/vsp5"

echo "== [3] apply DEFERRED exports override (won't crash boot) ==" | tee -a "$OUT/log.txt"
cp -f "$W" "$OUT/${W}.bak_before_defer_${TS}"
python3 - <<'PY'
from pathlib import Path
import sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P463FIXB_DEFER_EXPORTS_V1"
if MARK in s:
    print("[OK] already patched defer exports")
    sys.exit(0)

block = r'''
# --- VSP_P463FIXB_DEFER_EXPORTS_V1 ---
def _vsp_p463fixb_install_exports_if_app_ready():
    """
    Safe: do nothing unless global 'app' exists and looks like a Flask app.
    Never crash import/boot.
    """
    try:
        _app = globals().get("app", None)
        if _app is None:
            return False
        # crude checks
        if not hasattr(_app, "url_map") or not hasattr(_app, "add_url_rule"):
            return False

        # if already installed, skip
        if getattr(_app, "_vsp_p463fixb_exports_installed", False):
            return True

        from flask import request, jsonify, send_file
        import os, tarfile, hashlib
        from pathlib import Path

        def _candidate_roots():
            roots = [
                Path("/home/test/Data/SECURITY_BUNDLE"),
                Path("/home/test/Data/SECURITY_BUNDLE/out"),
                Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
                Path(__file__).resolve().parent / "out_ci",
            ]
            out=[]
            seen=set()
            for r in roots:
                try: r=r.resolve()
                except Exception: pass
                k=str(r)
                if k in seen: continue
                seen.add(k)
                if r.exists(): out.append(r)
            return out

        def _latest_rid():
            best=None
            for root in ["/home/test/Data/SECURITY_BUNDLE", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]:
                if not os.path.isdir(root):
                    continue
                for dirpath, dirnames, _ in os.walk(root):
                    if "/.venv/" in dirpath or "/venv/" in dirpath or "/node_modules/" in dirpath:
                        dirnames[:] = []
                        continue
                    for dn in dirnames:
                        if dn.startswith("VSP_CI_"):
                            if best is None or dn > best:
                                best = dn
                    # prune depth
                    if dirpath.count(os.sep) - root.count(os.sep) > 6:
                        dirnames[:] = []
            return best

        def _find_run_dir(rid: str):
            if not rid:
                return None
            rid=str(rid).strip()
            for base in _candidate_roots():
                try:
                    for d in base.rglob(rid):
                        if d.is_dir() and d.name == rid:
                            return d
                except Exception:
                    pass
            return None

        def _pick_csv(run_dir: Path):
            for f in (run_dir/"reports"/"findings_unified.csv", run_dir/"report"/"findings_unified.csv", run_dir/"findings_unified.csv"):
                try:
                    if f.is_file() and f.stat().st_size > 0:
                        return f
                except Exception:
                    pass
            return None

        def _cache_dir():
            d = Path(__file__).resolve().parent / "out_ci" / "exports_cache"
            d.mkdir(parents=True, exist_ok=True)
            return d

        def _build_tgz(run_dir: Path, rid: str):
            rid=str(rid).strip() or "RID_UNKNOWN"
            out = _cache_dir()/f"export_{rid}.tgz"
            tmp = _cache_dir()/f".tmp_export_{rid}.{os.getpid()}.tgz"
            try:
                if out.is_file() and out.stat().st_size > 0:
                    return out
            except Exception:
                pass

            include = [
                "SUMMARY.txt",
                "run_manifest.json",
                "run_evidence_index.json",
                "verdict_4t.json",
                "run_gate.json",
                "reports/run_gate_summary.json",
                "reports/findings_unified.json",
                "reports/findings_unified.csv",
                "reports/findings_unified.sarif",
                "findings_unified.json",
                "findings_unified.csv",
                "findings_unified.sarif",
                "reports",
            ]
            with tarfile.open(tmp, "w:gz") as tf:
                for rel in include:
                    pth = run_dir/rel
                    if not pth.exists():
                        continue
                    if pth.is_dir():
                        for sub in pth.rglob("*"):
                            if sub.is_file():
                                tf.add(str(sub), arcname=f"{rid}/{sub.relative_to(run_dir)}", recursive=False)
                    else:
                        tf.add(str(pth), arcname=f"{rid}/{pth.relative_to(run_dir)}", recursive=False)

            if not tmp.is_file() or tmp.stat().st_size == 0:
                try: tmp.unlink(missing_ok=True)
                except Exception: pass
                return None
            tmp.replace(out)
            return out

        def _sha256(path: Path):
            h=hashlib.sha256()
            with open(path,"rb") as f:
                for chunk in iter(lambda:f.read(1024*1024), b""):
                    h.update(chunk)
            return h.hexdigest()

        def export_csv():
            rid = (request.args.get("rid","") or "").strip() or (_latest_rid() or "")
            if not rid:
                return jsonify({"ok":0,"err":"no rid (auto latest failed)"}), 400
            run_dir=_find_run_dir(rid)
            if not run_dir:
                return jsonify({"ok":0,"err":"rid not found","rid":rid}), 404
            f=_pick_csv(run_dir)
            if not f:
                return jsonify({"ok":0,"err":"findings_unified.csv not found","rid":rid,"run_dir":str(run_dir)}), 404
            return send_file(str(f), mimetype="text/csv", as_attachment=True, download_name=f"findings_unified_{rid}.csv")

        def export_tgz():
            rid = (request.args.get("rid","") or "").strip() or (_latest_rid() or "")
            if not rid:
                return jsonify({"ok":0,"err":"no rid (auto latest failed)"}), 400
            run_dir=_find_run_dir(rid)
            if not run_dir:
                return jsonify({"ok":0,"err":"rid not found","rid":rid}), 404
            tgz=_build_tgz(run_dir, rid)
            if not tgz:
                return jsonify({"ok":0,"err":"failed to build tgz","rid":rid}), 500
            return send_file(str(tgz), mimetype="application/gzip", as_attachment=True, download_name=f"vsp_export_{rid}.tgz")

        def sha256_api():
            rid = (request.args.get("rid","") or "").strip() or (_latest_rid() or "")
            if not rid:
                return jsonify({"ok":0,"err":"no rid (auto latest failed)"}), 400
            run_dir=_find_run_dir(rid)
            if not run_dir:
                return jsonify({"ok":0,"err":"rid not found","rid":rid}), 404
            tgz=_build_tgz(run_dir, rid)
            if not tgz:
                return jsonify({"ok":0,"err":"failed to build tgz","rid":rid}), 500
            return jsonify({"ok":1,"rid":rid,"file":tgz.name,"bytes":tgz.stat().st_size,"sha256":_sha256(tgz)})

        def _override(path, handler):
            # replace if exists; else add
            for rule in list(_app.url_map.iter_rules()):
                if rule.rule == path and "GET" in rule.methods:
                    _app.view_functions[rule.endpoint] = handler
                    return ("replaced", rule.endpoint)
            ep = "vsp_p463fixb_" + path.strip("/").replace("/","_")
            _app.add_url_rule(path, endpoint=ep, view_func=handler, methods=["GET"])
            return ("added", ep)

        _override("/api/vsp/export_csv", export_csv)
        _override("/api/vsp/export_tgz", export_tgz)
        _override("/api/vsp/sha256", sha256_api)

        _app._vsp_p463fixb_exports_installed = True
        return True
    except Exception:
        # must never crash boot
        return False

# Try install now (safe), also will be called by request hooks if available
_vsp_p463fixb_install_exports_if_app_ready()
# --- /VSP_P463FIXB_DEFER_EXPORTS_V1 ---
'''

# append to end (safest; avoids import-time NameError)
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended defer exports block")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"
ok "py_compile $W PASS"

echo "== [4] restart and verify exports ==" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

up=0
for i in $(seq 1 20); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" -o /dev/null; then up=1; break; fi
  sleep 1
done
[ "$up" -eq 1 ] || {
  warn "still not reachable"
  sudo systemctl status "$SVC" --no-pager > "$OUT/status_after_defer.txt" 2>&1 || true
  sudo journalctl -u "$SVC" -n 200 --no-pager > "$OUT/journal_after_defer.txt" 2>&1 || true
  err "service not up after defer patch; see $OUT/journal_after_defer.txt"
}
ok "UI up"

echo "== GET /api/vsp/sha256 ==" | tee -a "$OUT/log.txt"
curl -sS --connect-timeout 2 --max-time 20 "$BASE/api/vsp/sha256" | head -c 240 | tee -a "$OUT/log.txt"
echo "" | tee -a "$OUT/log.txt"

echo "== headers /api/vsp/export_csv ==" | tee -a "$OUT/log.txt"
curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 20 "$BASE/api/vsp/export_csv" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"

echo "== headers /api/vsp/export_tgz ==" | tee -a "$OUT/log.txt"
curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 20 "$BASE/api/vsp/export_tgz" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"

ok "DONE: $OUT/log.txt"
