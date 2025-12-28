#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway_exportpdf_only.py"

echo "== [A] restore from latest bak_exporthead (if exists) =="
BAK="$(ls -1t ${F}.bak_exporthead_* 2>/dev/null | head -n1 || true)"
if [ -n "${BAK}" ]; then
  cp -f "${BAK}" "${F}"
  echo "[OK] restored ${F} <= ${BAK}"
else
  echo "[WARN] no ${F}.bak_exporthead_* found; trying to remove broken marker block"
  # best-effort remove the marker chunk if it exists
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway_exportpdf_only.py")
t=p.read_text(encoding="utf-8", errors="ignore")
# remove the injected marker chunk if present (even if inserted mid-line)
t2=re.sub(r"\s*# === EXPORT_HEAD_SUPPORT_V1 ===.*?return \[b\"\"\]\s*", "\n", t, flags=re.S)
p.write_text(t2, encoding="utf-8")
print("[OK] attempted cleanup")
PY
fi

echo "== [B] inject HEAD support correctly (after fmt line) =="
python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway_exportpdf_only.py")
t=p.read_text(encoding="utf-8", errors="ignore")

if "EXPORT_HEAD_SUPPORT_V1" in t:
    print("[OK] already has EXPORT_HEAD_SUPPORT_V1, skip")
    raise SystemExit(0)

lines = t.splitlines(True)

# find the run_export_v3 block and the fmt assignment line
idx_export = None
idx_fmt = None
for i,ln in enumerate(lines):
    if 'if path.startswith("/api/vsp/run_export_v3/")' in ln:
        idx_export = i
        break
if idx_export is None:
    raise SystemExit("[ERR] cannot find run_export_v3 block")

for i in range(idx_export, min(idx_export+120, len(lines))):
    if re.search(r'^\s*fmt\s*=\s*\(q\.get\("fmt"', lines[i]):
        idx_fmt = i
        break
if idx_fmt is None:
    raise SystemExit("[ERR] cannot find fmt assignment line inside export block")

indent = re.match(r'^(\s*)', lines[idx_fmt]).group(1)

ins = (
    f"{indent}# === EXPORT_HEAD_SUPPORT_V1 ===\n"
    f"{indent}# UI commercial probes export availability via HEAD; serve headers only.\n"
    f"{indent}if method == \"HEAD\":\n"
    f"{indent}    rid = path.split(\"/api/vsp/run_export_v3/\", 1)[1].strip(\"/\")\n"
    f"{indent}    ci_dir = _resolve_ci_dir(rid)\n"
    f"{indent}    fmt2 = fmt or \"html\"\n"
    f"{indent}    if fmt2 == \"pdf\":\n"
    f"{indent}        pdf = _pick_pdf(ci_dir) if ci_dir else \"\"\n"
    f"{indent}        if pdf and os.path.isfile(pdf):\n"
    f"{indent}            start_response(\"200 OK\", [\n"
    f"{indent}                (\"Content-Type\",\"application/pdf\"),\n"
    f"{indent}                (\"X-VSP-EXPORT-AVAILABLE\",\"1\"),\n"
    f"{indent}                (\"X-VSP-EXPORT-FILE\", os.path.basename(pdf)),\n"
    f"{indent}                (\"X-VSP-WSGI-LAYER\",\"EXPORTPDF_ONLY\"),\n"
    f"{indent}            ])\n"
    f"{indent}            return [b\"\"]\n"
    f"{indent}        start_response(\"200 OK\", [\n"
    f"{indent}            (\"Content-Type\",\"application/json\"),\n"
    f"{indent}            (\"X-VSP-EXPORT-AVAILABLE\",\"0\"),\n"
    f"{indent}            (\"X-VSP-WSGI-LAYER\",\"EXPORTPDF_ONLY\"),\n"
    f"{indent}        ])\n"
    f"{indent}        return [b\"\"]\n"
    f"{indent}    start_response(\"200 OK\", [\n"
    f"{indent}        (\"Content-Type\",\"application/json\"),\n"
    f"{indent}        (\"X-VSP-EXPORT-AVAILABLE\",\"1\"),\n"
    f"{indent}        (\"X-VSP-WSGI-LAYER\",\"EXPORTPROBE_HEAD_V1\"),\n"
    f"{indent}    ])\n"
    f"{indent}    return [b\"\"]\n"
)

# insert AFTER the fmt line (as a new block)
lines.insert(idx_fmt+1, ins)
p.write_text("".join(lines), encoding="utf-8")
print("[OK] injected EXPORT_HEAD_SUPPORT_V1 after fmt line at", idx_fmt+1)
PY

echo "== [C] compile + restart 8910 =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
