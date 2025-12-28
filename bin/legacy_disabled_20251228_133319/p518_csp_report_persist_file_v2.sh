#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p518_${TS}"
mkdir -p "$OUT"
cp -f "$APP" "$OUT/${APP}.bak_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P516B_CSP_REPORT_PERSIST_FILE_V2"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

lines = s.splitlines(True)

# Ensure imports exist (best-effort, non-destructive)
if "from pathlib import Path" not in s:
    # put near top (after first block of imports) - safest: prepend
    lines.insert(0, "from pathlib import Path\n")

# We assume P512 already added endpoint; patch inside function by inserting before return {"ok": True}
out_lines = []
in_func = False
func_indent = ""
patched = False

for i,ln in enumerate(lines):
    if re.match(r'^\s*def\s+api_ui_csp_report_v1\s*\(\s*\)\s*:\s*$', ln):
        in_func = True
        func_indent = re.match(r'^(\s*)', ln).group(1)
        out_lines.append(ln)
        continue

    if in_func:
        # detect leaving function by dedent (new def or decorator at same/less indent)
        if (ln.startswith(func_indent) and re.match(r'^\s*@app\.route\(|^\s*def\s+', ln)) and ("return" not in ln):
            in_func = False

    if in_func and (not patched) and re.match(r'^\s*return\s+\{\s*"ok"\s*:\s*True\s*\}\s*$', ln):
        # Insert persist block with SAME indentation as return line
        ind = re.match(r'^(\s*)', ln).group(1)
        block = [
            f"{ind}# {MARK}\n",
            f"{ind}try:\n",
            f"{ind}    log_path = \"/home/test/Data/SECURITY_BUNDLE/ui/out_ci/csp_reports.log\"\n",
            f"{ind}    Path(\"/home/test/Data/SECURITY_BUNDLE/ui/out_ci\").mkdir(parents=True, exist_ok=True)\n",
            f"{ind}    # truncate long fields\n",
            f"{ind}    for k in (\"document-uri\",\"blocked-uri\",\"violated-directive\",\"original-policy\"):\n",
            f"{ind}        if k in out and isinstance(out[k], str) and len(out[k]) > 800:\n",
            f"{ind}            out[k] = out[k][:800]\n",
            f"{ind}    with open(log_path, \"a\", encoding=\"utf-8\") as f:\n",
            f"{ind}        f.write(json.dumps(out, ensure_ascii=False) + \"\\\\n\")\n",
            f"{ind}except Exception:\n",
            f"{ind}    pass\n",
        ]
        out_lines.extend(block)
        out_lines.append(ln)
        patched = True
        continue

    out_lines.append(ln)

if not patched:
    raise SystemExit("[ERR] cannot find return {\"ok\": True} inside api_ui_csp_report_v1()")

app.write_text("".join(out_lines), encoding="utf-8")
print("[OK] patched", app)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile $APP"
sudo systemctl restart "$SVC"
echo "[OK] restarted"

# verify persist
curl -sS -X POST -H 'Content-Type: application/json' \
  --data '{"csp-report":{"document-uri":"persist-test","blocked-uri":"x","violated-directive":"script-src"}}' \
  "$BASE/api/ui/csp_report_v1" >/dev/null

echo "== tail csp_reports.log =="
tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/csp_reports.log || true
