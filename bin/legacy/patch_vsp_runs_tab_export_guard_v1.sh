#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/js/vsp_runs_tab_v1.js"

cp "$JS" "$JS.bak_export_guard_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_runs_tab_v1.js")
txt = p.read_text(encoding="utf-8")

old = '''// VSP_RUNS_EXPORT_HELPERS_V1_BEGIN
const VSP_RUN_EXPORT_BASE = "/api/vsp/run_export_v3";

function vspExportRun(runId, fmt) {
  const url = VSP_RUN_EXPORT_BASE
'''
new = '''// VSP_RUNS_EXPORT_HELPERS_V1_BEGIN
if (!window.VSP_RUN_EXPORT_BASE) {
  window.VSP_RUN_EXPORT_BASE = "/api/vsp/run_export_v3";
}

function vspExportRun(runId, fmt) {
  const url = window.VSP_RUN_EXPORT_BASE
'''

if old not in txt:
    print("[ERR] pattern not found, không patch được.")
    raise SystemExit(1)

p.write_text(txt.replace(old, new), encoding="utf-8")
print("[OK] Patched vsp_runs_tab_v1.js – export guard.")
PY
