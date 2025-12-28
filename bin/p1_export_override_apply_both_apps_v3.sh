#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

FILES=(wsgi_vsp_ui_gateway.py vsp_demo_app.py)

TS="$(date +%Y%m%d_%H%M%S)"
for F in "${FILES[@]}"; do
  [ -f "$F" ] || continue
  cp -f "$F" "${F}.bak_export_override_v3_${TS}"
  echo "[BACKUP] ${F}.bak_export_override_v3_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile

MARK="VSP_P1_EXPORT_FORCE_OVERRIDE_HOTFIX_V3"

blk = textwrap.dedent(r"""
# ===================== VSP_P1_EXPORT_FORCE_OVERRIDE_HOTFIX_V3 =====================
# Apply export override to the *actual* Flask app(s) present in this module.
try:
    import re as _re, json as _json, tarfile as _tarfile
    from pathlib import Path as _Path
    from flask import request as _req, send_file as _send_file, jsonify as _jsonify

    def _vsp__pick_apps_v3():
        apps=[]
        for k,v in list(globals().items()):
            try:
                if hasattr(v, "url_map") and hasattr(v, "view_functions"):
                    apps.append(v)
            except Exception:
                pass
        # also common names
        for k in ("app","application","_app"):
            v = globals().get(k)
            if v is not None and v not in apps:
                try:
                    if hasattr(v, "url_map") and hasattr(v, "view_functions"):
                        apps.append(v)
                except Exception:
                    pass
        return apps

    def _vsp__norm_rid_v3(rid0: str) -> str:
        rid0 = (rid0 or "").strip()
        m = _re.search(r'(\d{8}_\d{6})', rid0)
        return (m.group(1) if m else rid0.replace("VSP_CI_RUN_","").replace("VSP_CI_","").replace("RUN_","")).strip()

    def _vsp__rel_meta_v3():
        try:
            ui_root = _Path(__file__).resolve().parent
            cands = [
                ui_root/"out_ci"/"releases"/"release_latest.json",
                ui_root/"out"/"releases"/"release_latest.json",
                ui_root.parent/"out_ci"/"releases"/"release_latest.json",
                ui_root.parent/"out"/"releases"/"release_latest.json",
            ]
            for f in cands:
                if f.exists():
                    j = _json.loads(f.read_text(encoding="utf-8", errors="replace"))
                    return {
                        "ts": (j.get("ts") or j.get("timestamp") or ""),
                        "sha": (j.get("sha") or j.get("sha256") or ""),
                    }
        except Exception:
            pass
        return {"ts":"", "sha":""}

    def _vsp__resolve_run_dir_v3(rid0: str, rid_norm: str) -> str:
        # prefer existing helper if present
        try:
            if "_vsp__resolve_run_dir_for_export" in globals():
                x = globals()["_vsp__resolve_run_dir_for_export"](rid0, rid_norm)  # type: ignore
                if x:
                    return str(x)
        except Exception:
            pass
        # hard fallback (your confirmed real path)
        cand = _Path("/home/test/Data/SECURITY_BUNDLE/out") / (rid0 if rid0.startswith("RUN_") else f"RUN_{rid_norm}")
        if cand.exists() and cand.is_dir():
            return str(cand)
        # also check CI roots
        for root in [
            _Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            _Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        ]:
            try:
                if not root.exists():
                    continue
                for nm in [rid0, f"RUN_{rid_norm}", f"VSP_CI_RUN_{rid_norm}", f"VSP_CI_{rid_norm}", rid_norm]:
                    if not nm:
                        continue
                    c = root / nm
                    if c.exists() and c.is_dir():
                        return str(c)
            except Exception:
                pass
        return ""

    def _vsp__export_build_tgz_v3(run_dir: str, rid_norm: str) -> str:
        rd = _Path(run_dir)
        out = _Path("/tmp") / f"vsp_export_{rid_norm or rd.name}.tgz"
        try:
            if out.exists():
                out.unlink()
        except Exception:
            pass
        picks = [
            rd/"run_gate.json",
            rd/"run_gate_summary.json",
            rd/"findings_unified.json",
            rd/"reports",
            rd/"SUMMARY.txt",
        ]
        with _tarfile.open(out, "w:gz") as tf:
            base = f"{rid_norm or rd.name}"
            for x in picks:
                try:
                    if not x.exists():
                        continue
                    tf.add(str(x), arcname=f"{base}/{x.name}")
                except Exception:
                    continue
        return str(out)

    def api_vsp_run_export_v3_force_hotfix_v3(**kwargs):
        rid0 = (_req.args.get("rid") or _req.args.get("run_id") or _req.args.get("RID") or "").strip()
        if not rid0:
            rid0 = (kwargs.get("rid") or kwargs.get("run_id") or "").strip() if isinstance(kwargs, dict) else ""
        fmt = (_req.args.get("fmt") or "tgz").strip().lower()
        rid_norm = _vsp__norm_rid_v3(rid0)

        run_dir = _vsp__resolve_run_dir_v3(rid0, rid_norm)
        if not run_dir:
            return _jsonify({"ok": False, "error": "RUN_DIR_NOT_FOUND", "rid": rid0, "rid_norm": rid_norm, "hotfix": "export_override_v3"}), 404

        rel = _vsp__rel_meta_v3()
        suffix = ""
        if rel.get("ts"):
            t = str(rel["ts"]).replace(":","").replace("-","").replace("T","_")
            suffix += f"_rel-{t[:15]}"
        if rel.get("sha"):
            suffix += f"_sha-{str(rel['sha'])[:12]}"

        if fmt == "tgz":
            fp = _vsp__export_build_tgz_v3(run_dir, rid_norm or rid0)
            dl = f"VSP_EXPORT_{rid_norm or rid0}{suffix}.tgz"
            resp = _send_file(fp, as_attachment=True, download_name=dl, mimetype="application/gzip")
            try: resp.headers["X-VSP-HOTFIX"] = "export_override_v3"
            except Exception: pass
            return resp

        if fmt == "csv":
            rd = _Path(run_dir)
            cand = rd/"reports"/"findings_unified.csv"
            if not cand.exists():
                cand = rd/"reports"/"findings.csv"
            if not cand.exists():
                return _jsonify({"ok": False, "error": "CSV_NOT_FOUND", "rid": rid0, "rid_norm": rid_norm, "hotfix": "export_override_v3"}), 404
            dl = f"VSP_EXPORT_{rid_norm or rid0}{suffix}.csv"
            resp = _send_file(str(cand), as_attachment=True, download_name=dl, mimetype="text/csv")
            try: resp.headers["X-VSP-HOTFIX"] = "export_override_v3"
            except Exception: pass
            return resp

        if fmt == "html":
            rd = _Path(run_dir)
            cand = rd/"reports"/"findings_unified.html"
            if not cand.exists():
                cand = rd/"reports"/"index.html"
            if not cand.exists():
                return _jsonify({"ok": False, "error": "HTML_NOT_FOUND", "rid": rid0, "rid_norm": rid_norm, "hotfix": "export_override_v3"}), 404
            dl = f"VSP_EXPORT_{rid_norm or rid0}{suffix}.html"
            resp = _send_file(str(cand), as_attachment=True, download_name=dl, mimetype="text/html")
            try: resp.headers["X-VSP-HOTFIX"] = "export_override_v3"
            except Exception: pass
            return resp

        return _jsonify({"ok": False, "error": "FMT_UNSUPPORTED", "fmt": fmt, "hotfix":"export_override_v3"}), 400

    # Bind override to all endpoints whose rule is /api/vsp/run_export_v3 (or contains run_export_v3)
    for __A in _vsp__pick_apps_v3():
        try:
            eps=set()
            for rule in __A.url_map.iter_rules():
                rr = getattr(rule, "rule", "") or ""
                if rr == "/api/vsp/run_export_v3" or "run_export_v3" in rr:
                    eps.add(rule.endpoint)
            for ep in eps:
                try:
                    __A.view_functions[ep] = api_vsp_run_export_v3_force_hotfix_v3
                except Exception:
                    pass
        except Exception:
            pass
except Exception:
    pass
# ===================== /VSP_P1_EXPORT_FORCE_OVERRIDE_HOTFIX_V3 =====================
""").rstrip() + "\n"

for fname in ("wsgi_vsp_ui_gateway.py", "vsp_demo_app.py"):
    f = Path(fname)
    if not f.exists():
        continue
    s = f.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[OK] already patched:", fname)
        continue
    f.write_text(s.rstrip() + "\n\n" + blk, encoding="utf-8")
    print("[OK] appended:", fname)

# compile both if exist
for fname in ("wsgi_vsp_ui_gateway.py", "vsp_demo_app.py"):
    f = Path(fname)
    if f.exists():
        py_compile.compile(str(f), doraise=True)
print("[OK] py_compile OK (both)")
PY

systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== test export TGZ (should be 200 OR 404 with hotfix marker) =="
RID="RUN_20251120_130310"
curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
  "$BASE/api/vsp/run_export_v3?rid=$RID&fmt=tgz" \
  -w "\nHTTP=%{http_code}\n"
echo "== X-VSP-HOTFIX header =="
grep -i '^X-VSP-HOTFIX:' /tmp/vsp_exp_hdr.txt || true
echo "== Content-Disposition =="
grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
echo "== Body head =="
head -c 180 /tmp/vsp_exp_body.bin; echo
