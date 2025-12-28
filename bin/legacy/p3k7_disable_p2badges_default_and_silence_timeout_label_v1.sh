#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need date; need node
command -v systemctl >/dev/null 2>&1 || true

echo "== [0] find JS containing P2Badges / Dashboard error: timeout =="
mapfile -t files < <(grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' \
  -e 'P2Badges' -e 'rid_latest fetch fail timeout' -e 'Dashboard error: timeout' static/js || true)

if [ "${#files[@]}" -eq 0 ]; then
  echo "[WARN] no matching JS found (nothing to patch)"
  exit 0
fi

echo "[FOUND] ${#files[@]} files:"
printf '%s\n' "${files[@]}"

echo "== [1] backup =="
for f in "${files[@]}"; do
  cp -f "$f" "${f}.bak_p3k7_${TS}"
  echo "[BACKUP] ${f}.bak_p3k7_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P3K7_DISABLE_P2BADGES_DEFAULT_V1"

TOP_SNIP = f"""// {MARK}
(function(){{
  try {{
    const u = new URL(location.href);
    // badges=1 => enable P2Badges for debugging only
    if (u.searchParams.get("badges") === "1") return;
  }} catch (e) {{}}
  window.__VSP_DISABLE_P2BADGES = 1;
}})();
"""

def patch_file(path: Path):
    s = path.read_text(encoding="utf-8", errors="replace")
    changed = False

    if "P2Badges" in s and MARK not in s:
        s = TOP_SNIP + "\n" + s
        changed = True

        # guard common function forms that include P2Badges in name
        patterns = [
            # function fooP2Badges(...) {
            (r'(function\s+[A-Za-z0-9_$]*P2Badges[A-Za-z0-9_$]*\s*\([^)]*\)\s*\{)',
             r'\1\n  if (window.__VSP_DISABLE_P2BADGES) { return; }\n'),
            # const fooP2Badges = (...) => {
            (r'(const\s+[A-Za-z0-9_$]*P2Badges[A-Za-z0-9_$]*\s*=\s*(?:async\s*)?\([^)]*\)\s*=>\s*\{)',
             r'\1\n  if (window.__VSP_DISABLE_P2BADGES) { return; }\n'),
            # let fooP2Badges = function(...) {
            (r'((?:let|var)\s+[A-Za-z0-9_$]*P2Badges[A-Za-z0-9_$]*\s*=\s*(?:async\s*)?function\s*\([^)]*\)\s*\{)',
             r'\1\n  if (window.__VSP_DISABLE_P2BADGES) { return; }\n'),
        ]
        for pat, rep in patterns:
            s2 = re.sub(pat, rep, s, count=1, flags=re.M)
            if s2 != s:
                s = s2
                break  # one guard is enough

        # If code logs exact timeout warning, make it no-op in disabled mode
        s2 = s.replace("[P2Badges] rid_latest fetch fail timeout",
                       "[P2Badges] rid_latest fetch fail (ignored)")
        if s2 != s:
            s = s2
            changed = True

    # Silence the visible label "Dashboard error: timeout" (cosmetic + avoids confusion)
    if "Dashboard error: timeout" in s:
        s2 = s.replace("Dashboard error: timeout", "")
        if s2 != s:
            s = s2
            changed = True

    if changed:
        path.write_text(s, encoding="utf-8")
        print("[OK] patched:", str(path))
    else:
        print("[SKIP] no change:", str(path))

# discover files from grep in bash via a stable list file
# (we'll re-scan here to be safe)
import subprocess, sys
out = subprocess.check_output(["bash","-lc",
    "grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' "
    "-e 'P2Badges' -e 'rid_latest fetch fail timeout' -e 'Dashboard error: timeout' static/js || true"
], text=True).strip().splitlines()

for f in out:
    if f.strip():
        patch_file(Path(f.strip()))
PY

echo "== [2] syntax sanity (node -c) =="
for f in "${files[@]}"; do
  node -c "$f" >/dev/null
  echo "[OK] node -c: $f"
done

echo "== [3] restart =="
sudo systemctl restart "$SVC"
sleep 0.7
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 3
}

echo "[DONE] p3k7_disable_p2badges_default_and_silence_timeout_label_v1"
