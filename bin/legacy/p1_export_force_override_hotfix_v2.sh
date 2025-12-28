#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

APP="vsp_demo_app.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_export_override_v2_${TS}"
echo "[BACKUP] ${APP}.bak_export_override_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_EXPORT_FORCE_OVERRIDE_HOTFIX_V2"
if MARK in s:
    print("[OK] marker exists, skip append")
else:
    blk = textwrap.dedent(r"""
    # ===================== VSP_P1_EXPORT_FORCE_OVERRIDE_HOTFIX_V2 =====================
    # Robust override: find actual endpoint(s) bound to /api/vsp/run_export_v3 via url_map, then swap view_func.
    try:
        import re as _re, json as _json, tarfile as _tarfile
        from pathlib import Path as _Path
        from flask import request as _req, send_file as _send_file, jsonify as _jsonify

        def _vsp__pick_app_v2():
            for k in ("_app","app","application"):
                a = globals().get(k)
                if a is not None and hasattr(a, "view_functions") and hasattr(a, "url_map"):
                    return a
            return None

        def _vsp__norm_rid_v2(rid0: str) -> str:
            rid0 = (rid0 or "").strip()
            m = _re.search(r'(\d{8}_\d{6})', rid0)
            return (m.group(1) if m else rid0.replace("VSP_CI_RUN_","").replace("VSP_CI_","").replace("RUN_","")).strip()

        def _vsp__rel_meta_v2():
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

        def _vsp__resolve_run_dir_v2(rid0: str, rid_norm: str) -> str:
            # prefer existing helper if present
            try:
                if "_vsp__resolve_run_dir_for_export" in globals():
                    x = globals()["_vsp__resolve_run_dir_for_export"](rid0, rid_norm)  # type: ignore
                    if x:
                        return str(x)
            except Exception:
                pass
            # last resort: known root
            cand = _Path("/home/test/Data/SECURITY_BUNDLE/out") / (rid0 if rid0.startswith("RUN_") else f"RUN_{rid_norm}")
            if cand.exists() and cand.is_dir():
                return str(cand)
            return ""

        def _vsp__export_build_tgz_v2(run_dir: str, rid_norm: str) -> str:
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

        def api_vsp_run_export_v3_force_hotfix_v2(**kwargs):
            rid0 = (_req.args.get("rid") or _req.args.get("run_id") or _req.args.get("RID") or "").strip()
            if not rid0:
                # maybe passed as path arg
                rid0 = (kwargs.get("rid") or kwargs.get("run_id") or "").strip() if isinstance(kwargs, dict) else ""
            fmt = (_req.args.get("fmt") or "tgz").strip().lower()
            rid_norm = _vsp__norm_rid_v2(rid0)

            run_dir = _vsp__resolve_run_dir_v2(rid0, rid_norm)
            if not run_dir:
                return _jsonify({"ok": False, "error": "RUN_DIR_NOT_FOUND", "rid": rid0, "rid_norm": rid_norm, "hotfix": "v2"}), 404

            rel = _vsp__rel_meta_v2()
            suffix = ""
            if rel.get("ts"):
                t = str(rel["ts"]).replace(":","").replace("-","").replace("T","_")
                suffix += f"_rel-{t[:15]}"
            if rel.get("sha"):
                suffix += f"_sha-{str(rel['sha'])[:12]}"

            if fmt == "tgz":
                fp = _vsp__export_build_tgz_v2(run_dir, rid_norm or rid0)
                dl = f"VSP_EXPORT_{rid_norm or rid0}{suffix}.tgz"
                return _send_file(fp, as_attachment=True, download_name=dl, mimetype="application/gzip")

            if fmt == "csv":
                rd = _Path(run_dir)
                cand = rd/"reports"/"findings_unified.csv"
                if not cand.exists():
                    cand = rd/"reports"/"findings.csv"
                if not cand.exists():
                    return _jsonify({"ok": False, "error": "CSV_NOT_FOUND", "rid": rid0, "rid_norm": rid_norm, "hotfix": "v2"}), 404
                dl = f"VSP_EXPORT_{rid_norm or rid0}{suffix}.csv"
                return _send_file(str(cand), as_attachment=True, download_name=dl, mimetype="text/csv")

            if fmt == "html":
                rd = _Path(run_dir)
                cand = rd/"reports"/"findings_unified.html"
                if not cand.exists():
                    cand = rd/"reports"/"index.html"
                if not cand.exists():
                    return _jsonify({"ok": False, "error": "HTML_NOT_FOUND", "rid": rid0, "rid_norm": rid_norm, "hotfix": "v2"}), 404
                dl = f"VSP_EXPORT_{rid_norm or rid0}{suffix}.html"
                return _send_file(str(cand), as_attachment=True, download_name=dl, mimetype="text/html")

            return _jsonify({"ok": False, "error": "FMT_UNSUPPORTED", "fmt": fmt, "hotfix":"v2"}), 400

        __A = _vsp__pick_app_v2()
        if __A is not None:
            eps = set()
            for rule in __A.url_map.iter_rules():
                rr = getattr(rule, "rule", "") or ""
                if rr == "/api/vsp/run_export_v3" or "run_export_v3" in rr:
                    eps.add(rule.endpoint)
            # override ALL matched endpoints (most robust)
            for ep in eps:
                try:
                    __A.view_functions[ep] = api_vsp_run_export_v3_force_hotfix_v2
                except Exception:
                    pass
    except Exception:
        pass
    # ===================== /VSP_P1_EXPORT_FORCE_OVERRIDE_HOTFIX_V2 =====================
    """).rstrip() + "\n"
    s = s.rstrip() + "\n\n" + blk
    p.write_text(s, encoding="utf-8")
    print("[OK] appended hotfix override V2 block")

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== test export TGZ (expect 200 + Content-Disposition + maybe hotfix v2) =="
RID="RUN_20251120_130310"
curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
  "$BASE/api/vsp/run_export_v3?rid=$RID&fmt=tgz" \
  -w "\nHTTP=%{http_code}\n"
echo "CD:"
grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
echo "BODY_HEAD:"
head -c 160 /tmp/vsp_exp_body.bin; echo
