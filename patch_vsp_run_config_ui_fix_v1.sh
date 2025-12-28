#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

echo "[PATCH] VSP run config UI – harmonize TAB1/TAB2"

patch_one() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "[SKIP] $path không tồn tại"
    return
  fi

  python - << 'PY' "$path"
import sys, pathlib

path = pathlib.Path(sys.argv[1])
orig = path.read_text(encoding="utf-8")

marker = "    /* Run config bar (Target URL / SRC / Profile + RUN) */"
idx = orig.find(marker)
if idx == -1:
    print(f"[WARN] {path} không tìm thấy marker run-config CSS", file=sys.stderr)
    sys.exit(0)

inject = """
    /* TAB 2 – Runs & Reports: small run-config row (RUN SECURITY_BUNDLE) */
    .vsp-section-row.vsp-run-config {
      margin-bottom: 10px;
    }
    .vsp-card-run-config {
      padding: 10px 12px;
    }
    .vsp-card-run-config .vsp-card-header {
      margin-bottom: 6px;
    }
    .vsp-card-run-config .vsp-card-title {
      font-size: 12px;
    }
    .vsp-card-run-config .vsp-card-subtitle {
      margin: 2px 0 0;
      font-size: 10px;
      color: var(--vsp-text-muted);
    }
    .vsp-card-body {
      margin-top: 4px;
    }
    .vsp-run-grid {
      display: grid;
      grid-template-columns: 2fr 1.2fr 0.9fr;
      gap: 10px;
      align-items: flex-end;
    }
    .vsp-form-group label {
      font-size: 10px;
      color: var(--vsp-text-muted);
      display: block;
      margin-bottom: 4px;
    }
    .vsp-form-group small,
    .vsp-run-status {
      display: block;
      margin-top: 4px;
      font-size: 10px;
      color: var(--vsp-text-muted);
    }
    .vsp-form-actions {
      text-align: right;
    }
    .vsp-form-actions .vsp-btn {
      width: 100%;
      justify-content: center;
      margin-bottom: 4px;
    }
    @media (max-width: 1180px) {
      .vsp-run-grid {
        grid-template-columns: 1fr;
        align-items: stretch;
      }
      .vsp-form-actions {
        text-align: left;
      }
    }
"""

if inject in orig:
    print(f"[INFO] {path} đã có block run-config TAB2, bỏ qua.")
    sys.exit(0)

new = orig.replace(marker, marker + inject)

backup = path.with_suffix(path.suffix + ".bak_runconfig_v1")
backup.write_text(orig, encoding="utf-8")
path.write_text(new, encoding="utf-8")
print(f"[OK] Patched run-config CSS in {path}")
PY
}

patch_one "$ROOT/templates/index.html"
patch_one "$ROOT/my_flask_app/templates/vsp_5tabs_full.html"

echo "[PATCH] Done."
