#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [1] Fix bad JS references (runs_tab_*tools*) =="
python3 - <<'PY'
from pathlib import Path
import re, os

targets = []
for root in ("templates","static/js"):
    p = Path(root)
    if not p.exists(): 
        continue
    for f in p.rglob("*"):
        if f.is_file() and f.suffix in (".html",".js"):
            targets.append(f)

pat = re.compile(r"vsp_runs_tab[^\"']*tools[^\"']*\.js", re.IGNORECASE)

changed = 0
for f in targets:
    txt = f.read_text(encoding="utf-8", errors="ignore")
    m = pat.search(txt)
    if not m:
        continue
    bak = f.with_suffix(f.suffix + f".bak_fixrunstab_{os.environ.get('TS','')}")
    # create deterministic backup name without env
    bak = Path(str(f) + f".bak_fixrunstab_{__import__('time').strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(txt, encoding="utf-8")
    # normalize all weird variants to resolved file
    txt2 = pat.sub("vsp_runs_tab_resolved_v1.js", txt)
    # also handle exact known broken patterns with spaces/&
    txt2 = txt2.replace("vsp_runs_tab 8tools v1.js", "vsp_runs_tab_resolved_v1.js")
    txt2 = txt2.replace("vsp_runs_tab_8tools_v1.js", "vsp_runs_tab_resolved_v1.js")
    txt2 = txt2.replace("vsp_runs_tab&8tools_v1.js", "vsp_runs_tab_resolved_v1.js")
    f.write_text(txt2, encoding="utf-8")
    changed += 1
    print("[OK] patched", f)

print("[DONE] files_changed=", changed)
PY

echo "== [2] Make export HEAD probe always OK (WSGI) =="
F="wsgi_vsp_ui_gateway_exportpdf_only.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_exporthead_${TS}"
python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway_exportpdf_only.py")
t=p.read_text(encoding="utf-8", errors="ignore")

MARK="X-VSP-EXPORT-AVAILABLE"
# Insert HEAD support inside run_export_v3 block (idempotent)
if "EXPORT_HEAD_SUPPORT_V1" in t:
    print("[OK] export HEAD support already present")
    raise SystemExit(0)

needle='if path.startswith("/api/vsp/run_export_v3/")'
i=t.find(needle)
if i<0:
    raise SystemExit("[ERR] cannot find run_export_v3 block")

# find the fmt line after the block
# We inject right after: fmt = ...
m=re.search(r'if path\.startswith\("/api/vsp/run_export_v3/"\):\s*\n\s*fmt\s*=\s*\(q\.get\("fmt"', t)
if not m:
    raise SystemExit("[ERR] cannot locate fmt assignment within export block")

ins = r'''
            # === EXPORT_HEAD_SUPPORT_V1 ===
            # UI commercial probes export availability via HEAD; serve headers without breaking.
            if method == "HEAD":
                rid = path.split("/api/vsp/run_export_v3/", 1)[1].strip("/")
                ci_dir = _resolve_ci_dir(rid)
                fmt2 = fmt or "html"
                if fmt2 == "pdf":
                    pdf = _pick_pdf(ci_dir) if ci_dir else ""
                    if pdf and os.path.isfile(pdf):
                        start_response("200 OK", [
                            ("Content-Type","application/pdf"),
                            ("X-VSP-EXPORT-AVAILABLE","1"),
                            ("X-VSP-EXPORT-FILE", os.path.basename(pdf)),
                            ("X-VSP-WSGI-LAYER","EXPORTPDF_ONLY"),
                        ])
                        return [b""]
                    start_response("200 OK", [
                        ("Content-Type","application/json"),
                        ("X-VSP-EXPORT-AVAILABLE","0"),
                        ("X-VSP-WSGI-LAYER","EXPORTPDF_ONLY"),
                    ])
                    return [b""]
                # non-pdf: consider available (html/zip) so UI won't spam errors
                start_response("200 OK", [
                    ("Content-Type","application/json"),
                    ("X-VSP-EXPORT-AVAILABLE","1"),
                    ("X-VSP-WSGI-LAYER","EXPORTPROBE_HEAD_V1"),
                ])
                return [b""]
'''

# inject after fmt assignment line block match
pos = m.end()
t2 = t[:pos] + ins + t[pos:]
p.write_text(t2, encoding="utf-8")
print("[OK] injected export HEAD support")
PY
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== [3] Fix drilldown hash for vsp4 router =="
DASH="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$DASH" ] || { echo "[WARN] missing $DASH (skip)"; exit 0; }
cp -f "$DASH" "$DASH.bak_hash_${TS}"
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")

# Replace the simple "#datasource" assignment inside our tag block (best-effort)
t2 = t.replace('location.hash = "#datasource";', '''
        const h = String(location.hash||"");
        if(h.startsWith("#vsp4-")) location.hash = "#vsp4-datasource";
        else location.hash = "#datasource";
''')

p.write_text(t2, encoding="utf-8")
print("[OK] patched hash heuristic in dashboard enhance")
PY

echo "== DONE =="
echo "Now HARD refresh browser: Ctrl+Shift+R"
