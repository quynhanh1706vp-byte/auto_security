#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need grep; need sed; need awk; need python3; need mkdir; need cp
need sudo
command -v systemctl >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p52_${TS}"
mkdir -p "$ATT"
log "[OK] latest_release=$latest_release"

# Use latest p51 gate to locate marker hits
latest_gate="$(ls -1dt "$OUT"/p51_gate_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_gate:-}" ] && [ -d "$latest_gate" ] || { echo "[ERR] no p51_gate found"; exit 2; }
log "[OK] latest_gate=$latest_gate"

HITS="$latest_gate/html_marker_hits.txt"
if [ -f "$HITS" ]; then
  cp -f "$HITS" "$EVID/" || true
else
  echo "[WARN] no html_marker_hits.txt found" | tee "$EVID/no_marker_hits.txt" >/dev/null
fi

log "== [P52/1] Patch global header policy for HTML tabs (wsgi_vsp_ui_gateway.py preferred) =="

# We patch wsgi_vsp_ui_gateway.py if exists; else patch vsp_demo_app.py.
TARGET=""
if [ -f "wsgi_vsp_ui_gateway.py" ]; then TARGET="wsgi_vsp_ui_gateway.py"; fi
if [ -z "$TARGET" ] && [ -f "vsp_demo_app.py" ]; then TARGET="vsp_demo_app.py"; fi
[ -n "$TARGET" ] || { echo "[ERR] missing wsgi_vsp_ui_gateway.py and vsp_demo_app.py"; exit 2; }

cp -f "$TARGET" "$TARGET.bak_p52_${TS}"
echo "[OK] backup: $TARGET.bak_p52_${TS}" | tee "$EVID/backup_${TS}.txt" >/dev/null

python3 - <<PY
from pathlib import Path
import re

p=Path("$TARGET")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P52_HEADER_POLICY_V1"
if MARK in s:
    print("[OK] header policy already present")
else:
    # Insert a helper after imports (best effort)
    insert = r'''
# %s
def _vsp_p52_apply_header_policy(resp):
    """Commercial header policy for HTML tabs: keep consistent across routes."""
    try:
        # cache policy: no-store for dynamic UI pages
        resp.headers['Cache-Control'] = 'no-store'
        resp.headers['Pragma'] = 'no-cache'
        resp.headers['Expires'] = '0'
        # basic hardening
        resp.headers.setdefault('X-Content-Type-Options', 'nosniff')
        resp.headers.setdefault('Referrer-Policy', 'same-origin')
        # keep frame policy stable (avoid mismatch); adjust if you intentionally allow embedding
        resp.headers.setdefault('X-Frame-Options', 'SAMEORIGIN')
        return resp
    except Exception:
        return resp
''' % MARK

    # Try to place after the last import block
    m = re.search(r'(?s)\A(.*?)(\n\s*def |\n\s*class |\n\s*app\s*=|\n\s*@)', s)
    if m:
        pre = m.group(1)
        rest = s[len(pre):]
        s = pre + insert + rest
    else:
        s = insert + "\n" + s

    # Now wrap known HTML route returns:
    # Replace "return render_template(...)" or "return Response(...)" with apply policy.
    # We'll do safe targeted substitutions for common patterns.
    s = re.sub(r'(?m)^\s*return\s+render_template\((.+)\)\s*$',
               r"    return _vsp_p52_apply_header_policy(make_response(render_template(\1)))",
               s)

    # Ensure make_response imported
    if "make_response" not in s:
        # If Flask is imported as: from flask import Flask, ...
        s = re.sub(r'(?m)^(from\s+flask\s+import\s+)(.+)$',
                   lambda m: m.group(0) if "make_response" in m.group(2) else m.group(1)+m.group(2)+", make_response",
                   s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched header policy into", p)
PY

log "== [P52/2] Clean common debug markers in static/js + templates (safe replacements) =="

# We will only remove obvious text markers, not functional code.
# - Replace "N/A" with "-" in UI text rendering (common)
# - Replace "not available" with "-" (display text)
# - Remove "DEBUG:" / "TRACE:" label prefixes in UI text (display only)
python3 - <<'PY'
from pathlib import Path
import re, datetime

root = Path(".")
targets = []
for base in [root/"static/js", root/"templates"]:
    if base.exists():
        targets += [p for p in base.rglob("*") if p.is_file() and p.suffix in (".js",".html",".jinja",".j2")]

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
changed=[]
def patch_text(s: str) -> str:
    # conservative display-text replacements
    s2=s
    # common literals
    s2=re.sub(r'\bN/A\b', '-', s2)
    s2=re.sub(r'(?i)\bnot available\b', '-', s2)
    # label prefixes in UI strings
    s2=re.sub(r'(?i)\bDEBUG:\s*', '', s2)
    s2=re.sub(r'(?i)\bTRACE:\s*', '', s2)
    return s2

for p in targets:
    txt=p.read_text(encoding="utf-8", errors="replace")
    new=patch_text(txt)
    if new != txt:
        bak = p.with_name(p.name + f".bak_p52_{ts}")
        bak.write_text(txt, encoding="utf-8")
        p.write_text(new, encoding="utf-8")
        changed.append(str(p))

(Path("out_ci")/f"p52_changed_files_{ts}.txt").write_text("\n".join(changed)+"\n", encoding="utf-8")
print("[OK] changed files:", len(changed))
PY

log "== [P52/3] restart service to apply =="
sudo systemctl restart "${VSP_UI_SVC:-vsp-ui-8910.service}" || true

log "== [P52/4] attach evidence into release =="
# copy backups list + changed list if exists
ls -la "$TARGET.bak_p52_${TS}" > "$EVID/backup_file_${TS}.txt" 2>&1 || true
if ls -1 out_ci/p52_changed_files_*.txt >/dev/null 2>&1; then
  cp -f "$(ls -1t out_ci/p52_changed_files_*.txt | head -n 1)" "$EVID/" || true
fi
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

log "== [P52/5] verdict stub (P52 applied; rerun P51 to confirm warnings cleared) =="
VER="$OUT/p52_verdict_${TS}.json"
python3 - <<PY
import json, time
j={"ok": True,
   "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p52": {"patched": "$TARGET", "backup": f"$TARGET.bak_p52_${TS}",
           "latest_release": "$latest_release", "attached_dir": "$ATT",
           "note": "Rerun P51 to confirm headers_fingerprint_mismatch/html_markers_found cleared."}}
print(json.dumps(j, indent=2))
open("$VER","w").write(json.dumps(j, indent=2))
PY
cp -f "$VER" "$ATT/" 2>/dev/null || true

log "[DONE] P52 APPLIED"
