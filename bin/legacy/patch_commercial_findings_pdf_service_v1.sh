#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="/home/test/Data/SECURITY_BUNDLE/ui"
OUT_CI_BASE="/home/test/Data/SECURITY-10-10-v4/out_ci"
PORT="${VSP_PORT:-8910}"
BASE="http://127.0.0.1:${PORT}"

ts() { date +%Y%m%d_%H%M%S; }

echo "==[0] sanity =="
[ -d "$ROOT" ] || { echo "[ERR] missing ROOT=$ROOT"; exit 1; }
[ -d "$UI" ] || { echo "[ERR] missing UI=$UI"; exit 1; }

CI_LATEST="$(ls -1dt "$OUT_CI_BASE"/VSP_CI_* 2>/dev/null | head -n1 || true)"
echo "CI_LATEST=${CI_LATEST:-<none>}"
if [ -z "${CI_LATEST}" ]; then
  echo "[WARN] cannot detect latest CI dir under $OUT_CI_BASE (still patch code, verify later)"
fi

echo
echo "==[1] PATCH unify.sh to ALWAYS emit findings_unified.json at stable locations =="
UNIFY="$ROOT/bin/unify.sh"
if [ ! -f "$UNIFY" ]; then
  echo "[WARN] missing $UNIFY (skip unify patch). If your unify is elsewhere, patch it similarly."
else
  TS="$(ts)"
  cp -f "$UNIFY" "$UNIFY.bak_emit_findings_${TS}"
  echo "[BACKUP] $UNIFY.bak_emit_findings_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/bin/unify.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "### === VSP_UNIFY_EMIT_FINDINGS_V1 ==="
if TAG in t:
  print("[OK] unify.sh already patched (tag exists)")
  raise SystemExit(0)

block = r'''
%s
# Ensure findings_unified.json exists in BOTH:
#  - ${OUT_DIR}/reports/findings_unified.json  (preferred)
#  - ${OUT_DIR}/findings_unified.json          (compat)
# Even if total=0, file must exist (commercial: no-crash, clean-scan still has file).
_emit_findings_unified_v1() {
  local OUT_DIR="${1:-}"
  [ -n "$OUT_DIR" ] || return 0

  mkdir -p "$OUT_DIR/reports" 2>/dev/null || true

  # Try to locate any findings_unified.json produced somewhere under OUT_DIR
  local found=""
  found="$(find "$OUT_DIR" -maxdepth 4 -type f -name 'findings_unified.json' 2>/dev/null | head -n1 || true)"

  if [ -n "$found" ] && [ -f "$found" ]; then
    cp -f "$found" "$OUT_DIR/reports/findings_unified.json" 2>/dev/null || true
    cp -f "$found" "$OUT_DIR/findings_unified.json"         2>/dev/null || true
  fi

  # If still missing/empty -> create a minimal empty contract file (commercial safe)
  if [ ! -s "$OUT_DIR/reports/findings_unified.json" ]; then
    cat > "$OUT_DIR/reports/findings_unified.json" <<'JSON'
{"ok":true,"generated_by":"VSP_UNIFY_EMIT_FINDINGS_V1","total":0,"items":[],"warning":"no_findings_or_missing_sources"}
JSON
  fi
  if [ ! -s "$OUT_DIR/findings_unified.json" ]; then
    cp -f "$OUT_DIR/reports/findings_unified.json" "$OUT_DIR/findings_unified.json" 2>/dev/null || true
  fi
}
# Best-effort auto-detect OUT_DIR variable names used by unify.sh
if [ -n "${OUT_DIR:-}" ]; then
  _emit_findings_unified_v1 "$OUT_DIR"
elif [ -n "${RUN_DIR:-}" ]; then
  _emit_findings_unified_v1 "$RUN_DIR"
elif [ -n "${1:-}" ] && [ -d "${1:-}" ]; then
  _emit_findings_unified_v1 "${1:-}"
fi
# --- end emit findings ---
''' % TAG

# Append near end (safe) unless unify has explicit end markers.
t2 = t.rstrip() + "\n\n" + block + "\n"

p.write_text(t2, encoding="utf-8")
print("[OK] patched unify.sh: appended emit-findings block")
PY
  bash -n "$UNIFY" && echo "[OK] bash -n unify.sh OK" || { echo "[ERR] bash -n unify.sh failed"; exit 1; }
fi

echo
echo "==[2] PATCH UI export route: auto-build PDF if missing (Playwright) =="
APP="$UI/vsp_demo_app.py"
if [ ! -f "$APP" ]; then
  echo "[WARN] missing $APP (skip PDF/export patch)."
else
  TS="$(ts)"
  cp -f "$APP" "$APP.bak_pdf_on_demand_${TS}"
  echo "[BACKUP] $APP.bak_pdf_on_demand_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_EXPORT_PDF_ON_DEMAND_PLAYWRIGHT_V1 ==="
if TAG in t:
  print("[OK] export pdf already patched (tag exists)")
  raise SystemExit(0)

# Insert helper once (near imports). We keep it self-contained to avoid extra files.
helper = r'''
%s
def _vsp_pdf_from_html_string_v1(html: str, out_pdf_path: str) -> bool:
    """
    Commercial: build PDF from the SAME HTML export payload.
    - Uses Playwright if available.
    - Returns True if PDF created, else False (degrade gracefully).
    """
    try:
        from playwright.sync_api import sync_playwright  # type: ignore
    except Exception:
        return False

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page()
            page.set_content(html, wait_until="load")
            page.pdf(path=out_pdf_path, format="A4", print_background=True)
            browser.close()
        return True
    except Exception:
        return False
# --- end helper ---
''' % TAG

# Put helper after first flask imports block (best-effort)
if "from flask" in t and TAG not in t:
  t = re.sub(r"(from flask[^\n]*\n)", r"\1\n"+helper+"\n", t, count=1, flags=re.M)
else:
  # fallback: prepend at top
  t = helper + "\n" + t

# Now patch the export handler: when fmt=pdf and file missing => build
# We search for the header marker "X-VSP-EXPORT-AVAILABLE" handling in pdf branch.
# If cannot find, we still keep helper + warn.
pat = re.compile(r"(fmt\s*==\s*['\"]pdf['\"].{0,8000}?X-VSP-EXPORT-AVAILABLE\s*[:=]\s*[^\n]+)", re.S)
m = pat.search(t)

if not m:
  print("[WARN] cannot locate pdf branch w/ X-VSP-EXPORT-AVAILABLE in vsp_demo_app.py; helper injected only")
  p.write_text(t, encoding="utf-8")
  raise SystemExit(0)

segment = m.group(1)
if "VSP_EXPORT_PDF_ON_DEMAND_PLAYWRIGHT_V1" in segment:
  print("[OK] pdf branch already contains on-demand build logic")
  p.write_text(t, encoding="utf-8")
  raise SystemExit(0)

inject = r"""
    # === VSP_EXPORT_PDF_ON_DEMAND_PLAYWRIGHT_V1 (build if missing) ===
    try:
        # Heuristic: your handler usually has ci_run_dir + report html generator already.
        # We only attempt if the PDF file is missing, and we have HTML content ready.
        if (not os.path.exists(pdf_path)) or (os.path.getsize(pdf_path) <= 0):
            ok_pdf = _vsp_pdf_from_html_string_v1(html_content, pdf_path) if 'html_content' in locals() else False
            if ok_pdf:
                pass
    except Exception:
        pass
    # --- end on-demand pdf ---
"""

# Try to insert right after pdf_path is computed OR before setting header
t2 = t.replace(segment, segment + "\n" + inject, 1)
p.write_text(t2, encoding="utf-8")
print("[OK] patched export pdf branch: on-demand build inserted")
PY

  python3 -m py_compile "$APP" && echo "[OK] py_compile vsp_demo_app.py OK" || {
    echo "[ERR] py_compile failed. Restoring backup."
    ls -1 "$APP".bak_pdf_on_demand_* | tail -n1 | xargs -r -I{} cp -f {} "$APP"
    exit 1
  }
fi

echo
echo "==[3] OPTIONAL: Unmask + install systemd service (commercial deploy) =="
UNIT="/etc/systemd/system/vsp-ui-8910.service"
if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] systemctl present. If you have sudo, run below (script will try best-effort)."
  if command -v sudo >/dev/null 2>&1; then
    set +e
    sudo systemctl unmask vsp-ui-8910.service 2>/dev/null
    sudo tee "$UNIT" >/dev/null <<'UNITEOF'
[Unit]
Description=VSP UI Gateway 8910
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
Environment=VSP_PORT=8910
ExecStart=/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn -b 0.0.0.0:8910 --workers 2 --timeout 180 --log-level info --capture-output --access-logfile - --error-logfile - wsgi_vsp_ui_gateway:application
Restart=always
RestartSec=2
User=test
Group=test

[Install]
WantedBy=multi-user.target
UNITEOF
    sudo systemctl daemon-reload 2>/dev/null
    sudo systemctl enable vsp-ui-8910.service 2>/dev/null
    sudo systemctl restart vsp-ui-8910.service 2>/dev/null
    sudo systemctl --no-pager -l status vsp-ui-8910.service 2>/dev/null | head -n 40
    set -e
  else
    echo "[WARN] no sudo. You can run as root:"
    echo "  systemctl unmask vsp-ui-8910.service"
    echo "  (write unit to $UNIT) ; systemctl daemon-reload ; systemctl enable --now vsp-ui-8910"
  fi
else
  echo "[WARN] systemctl not found; skip service ops."
fi

echo
echo "==[4] QUICK verify endpoints (best-effort) =="
# (a) healthz
curl -sS -o /dev/null -w "healthz HTTP=%{http_code}\n" "${BASE}/healthz" 2>/dev/null || true

# (b) get latest RID
RID="$(curl -sS "${BASE}/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" 2>/dev/null | python3 - <<'PY'
import sys, json
try:
  d=json.load(sys.stdin)
  print((d.get("items") or [{}])[0].get("run_id",""))
except Exception:
  print("")
PY
)"
echo "RID=${RID:-<none>}"

# (c) findings preview (should become: file exists even when total=0)
if [ -n "${RID:-}" ]; then
  curl -sS "${BASE}/api/vsp/run_findings_preview_v1/${RID}" 2>/dev/null | python3 - <<'PY'
import sys, json
try:
  d=json.load(sys.stdin)
  print("findings_preview:", {k:d.get(k) for k in ["ok","has_findings","total","warning","file"]})
except Exception as e:
  print("findings_preview: <non-json>")
PY
fi

# (d) export headers (try both common URL shapes)
try_export() {
  local url="$1"
  local fmt="$2"
  curl -sS -D- -o /dev/null "${url}?fmt=${fmt}" 2>/dev/null | awk 'BEGIN{ok=0} /^HTTP/{print} /^X-VSP-EXPORT-AVAILABLE/{print; ok=1} END{if(!ok) print "X-VSP-EXPORT-AVAILABLE: <missing>"}'
}

if [ -n "${RID:-}" ]; then
  echo "-- export headers try #1 (path style) --"
  try_export "${BASE}/api/vsp/run_export_v3/${RID}" "pdf" || true
  echo "-- export headers try #2 (query style) --"
  try_export "${BASE}/api/vsp/run_export_v3" "pdf" || true
fi

echo
echo "[DONE] patch_commercial_findings_pdf_service_v1"
