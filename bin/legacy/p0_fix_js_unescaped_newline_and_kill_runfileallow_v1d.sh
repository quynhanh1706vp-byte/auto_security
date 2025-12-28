#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v node >/dev/null 2>&1 || echo "[WARN] node not found; skip node --check"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

FILES=(
  static/js/vsp_tabs4_autorid_v1.js
  static/js/vsp_dashboard_luxe_v1.js
  static/js/vsp_dash_only_v1.js
)

for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_v1d_${TS}"
    ok "backup: ${f}.bak_v1d_${TS}"
  else
    warn "missing: $f"
  fi
done

python3 - <<'PY'
from pathlib import Path
import re

FILES = [
  "static/js/vsp_tabs4_autorid_v1.js",
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_dash_only_v1.js",
]

def sanitize_unescaped_newlines_in_double_quotes(src: str) -> str:
  # Minimal state machine: fix newline inside "..." literals (cause of Firefox SyntaxError)
  out = []
  in_dq = False
  esc = False
  # also handle CRLF by normalizing \r away
  src = src.replace("\r\n", "\n").replace("\r", "\n")
  for ch in src:
    if not in_dq:
      if ch == '"':
        in_dq = True
        esc = False
      out.append(ch)
      continue

    # in double-quoted string
    if esc:
      esc = False
      out.append(ch)
      continue
    if ch == '\\':
      esc = True
      out.append(ch)
      continue
    if ch == '"':
      in_dq = False
      out.append(ch)
      continue
    if ch == "\n":
      # replace literal linebreak inside string with \n escape and DO NOT keep newline
      out.append("\\n")
      continue
    out.append(ch)
  return "".join(out)

def kill_runfileallow_callers(src: str) -> str:
  x = src

  # Replace *real* call patterns only (query contains rid=...).
  # Keep any dev text/toast strings as-is if they don't match '?rid='.
  x = re.sub(r'(/api/vsp/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=run_gate_summary\.json)',
             r'/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}', x)
  x = x.replace('/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json',
                '/api/vsp/run_gate_summary_v1?rid=" + encodeURIComponent(rid)')
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`',
                '`/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}`')

  # run_gate.json: if any code was probing it, point to dashboard_v3 (commercial) as fallback
  x = x.replace('/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate.json',
                '/api/vsp/dashboard_v3?rid=" + encodeURIComponent(rid)')
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json`',
                '`/api/vsp/dashboard_v3?rid=${encodeURIComponent(rid)}`')

  # findings_unified.json calls: use findings_page_v3 paging
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&limit=25`',
                '`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=25&offset=0`')
  x = x.replace('/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=findings_unified.json',
                '/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid) + "&limit=50&offset=0')

  return x

def patch(path: str):
  p = Path(path)
  if not p.exists():
    print("[WARN] missing:", path)
    return
  s = p.read_text(encoding="utf-8", errors="ignore")
  s2 = sanitize_unescaped_newlines_in_double_quotes(s)
  s3 = kill_runfileallow_callers(s2)
  if s3 != s:
    p.write_text(s3, encoding="utf-8")
    print("[OK] patched:", path, "changed_bytes=", (len(s3)-len(s)))
  else:
    print("[OK] nochange:", path)

for f in FILES:
  patch(f)
PY

# Syntax check (best-effort)
if command -v node >/dev/null 2>&1; then
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    node --check "$f" && ok "node --check OK: $f" || warn "node --check FAIL: $f"
  done
else
  warn "node not installed; skipping node --check"
fi

# Restart service
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
  sleep 0.4 || true
fi

echo "== [SMOKE] should be empty (actual callers only) =="
grep -RIn --line-number '/api/vsp/run_file_allow\?rid=' static/js | head -n 40 || true

echo "== [SMOKE] show remaining mentions (may include toast/help text) =="
grep -RIn --line-number '/api/vsp/run_file_allow' static/js | head -n 40 || true

echo "== [DONE] Reload /vsp5 and confirm no SyntaxError + no run_file_allow XHR =="
