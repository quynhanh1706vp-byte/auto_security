#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
NEW_MS=

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need date; need node
command -v systemctl >/dev/null 2>&1 || true

echo "== [0] collect dashboard-related JS files =="
# keep it focused: dashboard/charts/tabs5
mapfile -t files < <(
  (grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' \
     -e 'Dashboard' -e 'dashboard' -e 'charts' -e 'watchdog' -e 'P2Badges' \
     static/js \
   | grep -E 'vsp_.*(dashboard|charts|bundle_tabs5|tabs5).*\.js$' || true) \
  | sort -u
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "[WARN] no dashboard-related JS found"
  exit 0
fi

echo "[FOUND] ${#files[@]} files:"
printf '%s\n' "${files[@]}"

echo "== [1] backup =="
for f in "${files[@]}"; do
  cp -f "$f" "${f}.bak_p3k8_${TS}"
  echo "[BACKUP] ${f}.bak_p3k8_${TS}"
done

python3 - <<PY
from pathlib import Path
import re, os

MARK="VSP_P3K8_DASH_TIMEOUT_ONCE_V1"
NEW_MS=int(os.environ.get("NEW_MS","8000"))

def bump_timeouts(s: str) -> str:
    # setTimeout(() => ctrl.abort(), 800)
    s = re.sub(
        r'(setTimeout\\s*\\(\\s*[^\\)]*?\\babort\\s*\\(\\s*\\)\\s*[^\\)]*?,\\s*)(\\d{1,4})(\\s*\\))',
        lambda m: m.group(1) + (str(NEW_MS) if int(m.group(2)) <= 2000 else m.group(2)) + m.group(3),
        s,
        flags=re.I
    )
    # timeoutMs / timeout / timeout_ms assignments <=2000 -> NEW_MS
    s = re.sub(
        r'((?:timeoutMs|timeout_ms|timeout)\\s*[:=]\\s*)(\\d{1,4})',
        lambda m: m.group(1) + (str(NEW_MS) if int(m.group(2)) <= 2000 else m.group(2)),
        s,
        flags=re.I
    )
    return s

def wrap_once_guard(path: Path, s: str) -> str:
    # Only wrap dashboard/charts scripts; bundle_tabs5 we only bump timeouts + silence msg
    fname = path.name
    is_wrap = bool(re.search(r'(dashboard|charts)',$fname,re.I))
    if not is_wrap:
        return s

    # Avoid double wrapping
    if MARK in s:
        return s

    key = f"p3k8:{fname}"
    head = f"""// {MARK}
(function(){{
  try {{
    if (!location.pathname.includes("/vsp5")) return;
  }} catch(e) {{}}
  window.__VSP_ONCE = window.__VSP_ONCE || {{}};
  if (window.__VSP_ONCE[{key!r}]) return;
  window.__VSP_ONCE[{key!r}] = 1;
}})();
"""
    # Wrap whole file in a conditional block so "return" is possible (top-level return not allowed)
    wrapped = f"""{head}
if (typeof window !== "undefined") {{
  window.__VSP_ONCE = window.__VSP_ONCE || {{}};
}}
if (typeof window !== "undefined" && window.__VSP_ONCE && window.__VSP_ONCE[{key!r}] === 1) {{
  // already marked above; continue
}}
/*__VSP_P3K8_BEGIN__*/\n{s}\n/*__VSP_P3K8_END__*/\n"""
    return wrapped

def patch_file(f: str):
    p=Path(f)
    s=p.read_text(encoding="utf-8", errors="replace")
    s0=s

    # 1) silence label text (cosmetic + avoids confusing state)
    if "Dashboard error: timeout" in s:
        s = s.replace("Dashboard error: timeout","")

    # 2) bump abort/timeout numbers
    s = bump_timeouts(s)

    # 3) once-guard wrap for dashboard/charts files
    s = wrap_once_guard(p, s)

    if s != s0:
        # put mark at top for non-wrapped files too
        if MARK not in s:
            s = f"// {MARK}\\n" + s
        p.write_text(s, encoding="utf-8")
        print("[OK] patched:", f)
    else:
        print("[SKIP] no change:", f)

files = ${files[@]!r}
# The bash heredoc passes files as a Python literal list? not possible. We'll re-scan in python:
import subprocess
out = subprocess.check_output(["bash","-lc",
  "grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' -e 'Dashboard' -e 'dashboard' -e 'charts' -e 'watchdog' -e 'P2Badges' static/js "
  "| grep -E 'vsp_.*(dashboard|charts|bundle_tabs5|tabs5).*\\.js$' | sort -u || true"
], text=True).splitlines()

for f in out:
    if f.strip():
        patch_file(f.strip())
PY
# export NEW_MS for python heredoc
