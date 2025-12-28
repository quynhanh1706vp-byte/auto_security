#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "$APP.bak_report_cio_parsefix_${TS}" && echo "[BACKUP] $APP.bak_report_cio_parsefix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

# Find the report endpoint and replace the renderer try-block
pat = re.compile(r"""
@app\.get\("/api/vsp/run_report_cio_v1/<rid>"\)\s*
def\s+api_vsp_run_report_cio_v1\(rid\):\s*
(?P<body>[\s\S]*?)
^\s*return\s+Response\(
""", re.M | re.X)

m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find api_vsp_run_report_cio_v1 block")

body = m.group("body")

# Replace the "build context" section starting at "# build context"
# up to before "from flask import render_template_string"
body2 = re.sub(
    r"""(?s)#\s*build\s*context.*?from\s+flask\s+import\s+render_template_string""",
    r"""# build context (robust: capture stdout/stderr + parse JSON block)
    import json, subprocess
    stdout = ""
    stderr = ""
    try:
        r = subprocess.run(
            [os.path.join(ui_root, "bin", "vsp_build_report_cio_v1.py"), rd, ui_root],
            capture_output=True,
            text=True
        )
        stdout = (r.stdout or "")
        stderr = (r.stderr or "")
        if r.returncode != 0:
            return jsonify({
                "ok": False, "rid": rid, "error": "renderer_rc_nonzero", "rc": r.returncode,
                "stdout_tail": stdout[-1500:], "stderr_tail": stderr[-1500:]
            }), 500

        txt = (stdout or "").strip()
        # extract the first JSON object from stdout
        a = txt.find("{")
        b = txt.rfind("}")
        if a < 0 or b < 0 or b <= a:
            return jsonify({
                "ok": False, "rid": rid, "error": "renderer_no_json",
                "stdout_head": txt[:500], "stderr_head": (stderr or "")[:500]
            }), 500

        ctx = json.loads(txt[a:b+1])
    except Exception as e:
        return jsonify({
            "ok": False, "rid": rid, "error": "renderer_failed",
            "detail": str(e),
            "stdout_head": (stdout or "")[:500],
            "stderr_head": (stderr or "")[:500]
        }), 500

    from flask import render_template_string""",
    body
)

if body2 == body:
    raise SystemExit("[ERR] did not patch (marker not found)")

# Rebuild the full file by swapping the body
s2 = s[:m.start("body")] + body2 + s[m.end("body"):]
p.write_text(s2, encoding="utf-8")
print("[OK] patched report cio renderer parse")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patch_report_cio_endpoint_fix_parse_v1"
