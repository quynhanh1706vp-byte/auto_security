#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_exportzip_v3_${TS}"
echo "[BACKUP] ${APP}.bak_exportzip_v3_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

APP = Path("vsp_demo_app.py")
s = APP.read_text(encoding="utf-8", errors="replace")

# strip older export blocks
def strip(text, mark):
    pat = re.compile(rf"\n# === {re.escape(mark)} ===.*?\n# === /{re.escape(mark)} ===\n", re.S)
    return pat.sub("\n", text)

for m in ["VSP_EXPORT_ZIP_P0_V1","VSP_EXPORT_ZIP_P0_V2","VSP_EXPORT_ZIP_P0_V2B"]:
    s = strip(s, m)

MARK="VSP_EXPORT_ZIP_P0_V3"
if MARK in s:
    print("[OK] already V3"); raise SystemExit(0)

inject = """
# === VSP_EXPORT_ZIP_P0_V3 ===
from flask import send_file, request
import json as _json
import time as _time
import zipfile as _zipfile
from pathlib import Path as _Path

def _vsp_export_find_candidates_p0_v3(run_dir: _Path):
    \"\"\"Return list of (src_path, arcname). Auto-discover key artifacts with guards.\"\"\"
    picks = []
    seen = set()

    def add(p: _Path, arc: str):
        if arc in seen:
            return
        try:
            if not p.is_file():
                return
            # size guard per file
            if p.stat().st_size > 50_000_000:
                return
        except Exception:
            return
        seen.add(arc)
        picks.append((p, arc))

    # (A) exact common locations
    for name in [
        "SUMMARY.txt","run_gate.json","run_gate_summary.json","run_manifest.json","run_evidence_index.json",
        "findings_unified.json","findings_unified.csv","findings_unified.sarif",
        "verdict_4t.json","nurl_audit_latest.json"
    ]:
        add(run_dir / name, name)
        add(run_dir / "reports" / name, f"reports/{name}")
        add(run_dir / "report" / name, f"report/{name}")

    # (B) auto-discover summaries & reports (depth-limited)
    # allowlist patterns
    allow_names = set([
        "SUMMARY.txt",
        "findings_unified.json","findings_unified.csv","findings_unified.sarif",
        "run_gate.json","run_gate_summary.json",
        "run_manifest.json","run_evidence_index.json",
        "index.html","report.html",
    ])

    # also include *_summary.json small files
    try:
        for p in run_dir.rglob("*_summary.json"):
            if p.is_file():
                try:
                    if p.stat().st_size <= 5_000_000:
                        add(p, str(p.relative_to(run_dir)))
                except Exception:
                    pass
    except Exception:
        pass

    # include allow_names anywhere under run_dir (first N hits each)
    counts = {}
    try:
        for p in run_dir.rglob("*"):
            if not p.is_file():
                continue
            nm = p.name
            if nm in allow_names:
                counts[nm] = counts.get(nm, 0) + 1
                # cap per filename to avoid explosion
                if counts[nm] <= 10:
                    add(p, str(p.relative_to(run_dir)))
    except Exception:
        pass

    # (C) always add a compact listing for audit (we will write separately too)
    return picks

def _vsp_export_build_listing_p0_v3(run_dir: _Path, max_lines: int = 8000) -> str:
    lines = []
    lines.append(f"run_dir={run_dir}")
    try:
        items = []
        for p in run_dir.rglob("*"):
            try:
                if p.is_file():
                    sz = p.stat().st_size
                    rp = str(p.relative_to(run_dir))
                    items.append((rp, sz))
            except Exception:
                pass
        items.sort(key=lambda x: x[0])
        lines.append(f"files={len(items)}")
        for i,(rp,sz) in enumerate(items[:max_lines]):
            lines.append(f"{sz}\\t{rp}")
        if len(items) > max_lines:
            lines.append(f"... truncated: {len(items)-max_lines} more")
    except Exception as e:
        lines.append(f"listing_error={e}")
    return "\\n".join(lines) + "\\n"

@app.get("/api/vsp/export_zip")
def vsp_export_zip_p0_v3():
    run_id = (request.args.get("run_id") or "").strip()
    if not run_id:
        return jsonify({"ok": False, "error": "missing run_id"}), 400

    ui_dir = _Path(__file__).resolve().parent
    sb = ui_dir.parent
    out_dir = sb / "out"
    run_dir = out_dir / run_id
    if not run_dir.is_dir():
        return jsonify({"ok": False, "error": "run_id not found", "run_dir": str(run_dir)}), 404

    exp_dir = ui_dir / "out_ci" / "exports"
    exp_dir.mkdir(parents=True, exist_ok=True)
    ts = _time.strftime("%Y%m%d_%H%M%S")
    zip_path = exp_dir / f"VSP_EXPORT_{run_id}_{ts}.zip"

    # selfcheck snapshot (best-effort)
    try:
        sc = selfcheck_p0().get_json()  # type: ignore
    except Exception as e:
        sc = {"ok": False, "error": f"selfcheck snapshot failed: {e}"}

    # findings fallback (UI unified) if run has none
    fallback_findings = None
    try:
        fallback_findings = _vsp_load_findings_unified_p0_v1()  # type: ignore
    except Exception:
        fallback_findings = None

    picks = _vsp_export_find_candidates_p0_v3(run_dir)
    listing = _vsp_export_build_listing_p0_v3(run_dir)

    # total guard (avoid huge zip)
    MAX_FILES = 250
    MAX_TOTAL = 80_000_000
    total = 0
    kept = []
    for src, arc in picks:
        try:
            sz = src.stat().st_size
        except Exception:
            continue
        if len(kept) >= MAX_FILES:
            break
        if total + sz > MAX_TOTAL:
            continue
        kept.append((src, arc))
        total += sz

    with _zipfile.ZipFile(zip_path, "w", compression=_zipfile.ZIP_DEFLATED) as zf:
        man = {
            "ok": True,
            "run_id": run_id,
            "run_dir": str(run_dir),
            "generated_at": ts,
            "picked_files": [arc for _, arc in kept],
            "picked_count": len(kept),
            "picked_total_bytes": total,
        }
        zf.writestr("MANIFEST.json", _json.dumps(man, indent=2, ensure_ascii=False) + "\\n")
        zf.writestr("AUDIT/selfcheck_p0_snapshot.json", _json.dumps(sc, indent=2, ensure_ascii=False) + "\\n")
        zf.writestr("AUDIT/run_dir_listing.tsv", listing)

        for src, arc in kept:
            try:
                zf.write(str(src), arc)
            except Exception:
                pass

        has_findings = any(arc.endswith("findings_unified.json") for _, arc in kept)
        if (not has_findings) and isinstance(fallback_findings, dict):
            try:
                zf.writestr("findings_unified.json", _json.dumps(fallback_findings, indent=2, ensure_ascii=False) + "\\n")
            except Exception:
                pass

    return send_file(str(zip_path), as_attachment=True, download_name=zip_path.name, mimetype="application/zip")
# === /VSP_EXPORT_ZIP_P0_V3 ===
"""

mm = re.search(r"^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s, flags=re.M)
if mm:
    s = s[:mm.start()] + "\n" + inject + "\n" + s[mm.start():]
else:
    s = s.rstrip() + "\n" + inject + "\n"

APP.write_text(s, encoding="utf-8")
print("[OK] injected VSP_EXPORT_ZIP_P0_V3")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 then retest export"
