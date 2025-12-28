#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "$APP.bak_report_importlib_${TS}" && echo "[BACKUP] $APP.bak_report_importlib_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

# Replace only the context-build block in api_vsp_run_report_cio_v1
# We look for "build context" comment and rewrite it to importlib loader.
pat = re.compile(r"(@app\.get\(\"/api/vsp/run_report_cio_v1/<rid>\"\)[\s\S]*?def\s+api_vsp_run_report_cio_v1\(rid\):[\s\S]*?)# build context[\s\S]*?from flask import render_template_string", re.M)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot locate report endpoint or build context marker")

head = m.group(1)

new_mid = r'''# build context (importlib: no subprocess, no JSON parse)
    import traceback, importlib.util
    try:
        ui_root = os.path.abspath(os.path.dirname(__file__))
        mod_path = os.path.join(ui_root, "bin", "vsp_build_report_cio_v1.py")
        if not os.path.isfile(mod_path):
            return jsonify({"ok": False, "rid": rid, "error": "renderer_missing", "path": mod_path}), 500

        spec = importlib.util.spec_from_file_location("vsp_build_report_cio_v1", mod_path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)  # type: ignore

        if not hasattr(mod, "build"):
            return jsonify({"ok": False, "rid": rid, "error": "renderer_no_build"}), 500

        ctx = mod.build(rd, ui_root)
    except Exception as e:
        return jsonify({"ok": False, "rid": rid, "error": "renderer_failed", "detail": str(e), "trace": traceback.format_exc()[-2000:]}), 500

    from flask import render_template_string
'''

# Find the original segment to replace (between '# build context' and 'from flask import render_template_string')
seg_pat = re.compile(r"# build context[\s\S]*?from flask import render_template_string", re.M)
whole = seg_pat.search(s[m.start(1):m.end()])
if not whole:
    raise SystemExit("[ERR] cannot find build context segment inside endpoint")

s2 = s[:m.start(1)] + head + new_mid + s[m.end(1)+whole.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched report endpoint to importlib renderer")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patch_report_cio_importlib_v1"
