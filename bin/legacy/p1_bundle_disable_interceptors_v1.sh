#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_disable_intr_${TS}"
echo "[BACKUP] ${JS}.bak_disable_intr_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DISABLE_INTERCEPTORS_V1"

# 0) Inject global kill-switch near top (idempotent)
if MARK not in s:
    inject = r"""/* %s
 * Commercial clean: disable fetch/XHR interceptors/normalize/rewrite in this bundle.
 * Dashboard contract must be direct: rid_latest_gate_root + run_gate_summary.json (no hooks).
 */
try { window.__vsp_disable_interceptors_v1 = true; } catch(_){}
""" % MARK
    # put after first /* ... */ header if any; else at very top
    m = re.search(r"/\*[\s\S]{0,2000}?\*/", s)
    if m:
        s = s[:m.end()] + "\n" + inject + s[m.end():]
    else:
        s = inject + "\n" + s

# 1) Canonicalize endpoints (remove reliance on rewrite hooks)
# Replace common legacy endpoints in string literals and template strings.
# Keep it conservative: only these exact paths.
repls = [
    (r"/api/vsp/latest_rid", "/api/vsp/rid_latest_gate_root"),
    (r"/api/vsp/rid_latest?", "/api/vsp/rid_latest_gate_root?"),
    (r"/api/vsp/rid_latest\"", "/api/vsp/rid_latest_gate_root\""),
    (r"/api/vsp/rid_latest'", "/api/vsp/rid_latest_gate_root'"),
]
for a,b in repls:
    s = s.replace(a,b)

# 2) Disable ALL assignments that override fetch
# Pattern: line that starts with optional spaces then window.fetch = ...
def guard_fetch_line(m):
    line = m.group(0)
    if "__vsp_disable_interceptors_v1" in line:
        return line
    # keep indentation
    indent = re.match(r"^\s*", line).group(0)
    return indent + "if (!window.__vsp_disable_interceptors_v1) " + line.lstrip()

s = re.sub(r"(?m)^\s*window\.fetch\s*=\s*(?:async\s*)?function\b", guard_fetch_line, s)
s = re.sub(r"(?m)^\s*window\.fetch\s*=\s*async\s*\(", guard_fetch_line, s)  # rare patterns

# 3) Disable ALL assignments that override XHR open
def guard_xhr_line(m):
    line = m.group(0)
    if "__vsp_disable_interceptors_v1" in line:
        return line
    indent = re.match(r"^\s*", line).group(0)
    return indent + "if (!window.__vsp_disable_interceptors_v1) " + line.lstrip()

s = re.sub(r"(?m)^\s*XMLHttpRequest\.prototype\.open\s*=\s*function\b", guard_xhr_line, s)

# 4) (Optional) soften any loud “enabled” logs
s = s.replace("[VSP] rungate normalize (fetch+XHR) enabled", "[VSP] rungate normalize DISABLED (commercial clean)")

# sanity: ensure kill-switch exists
if "window.__vsp_disable_interceptors_v1" not in s:
    raise SystemExit("inject failed: disable flag missing")

p.write_text(s, encoding="utf-8")
print("[OK] patched bundle: disable interceptors + canonicalize endpoints")
PY

# quick syntax check (node optional)
if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check passed"
else
  echo "[WARN] node not found, skipped syntax check"
fi

# restart service to pick up static (if needed)
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Now hard refresh /vsp5 (Ctrl+Shift+R)"
