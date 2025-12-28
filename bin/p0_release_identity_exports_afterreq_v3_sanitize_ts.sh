#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_relid_sanitize_${TS}"
echo "[BACKUP] ${WSGI}.bak_relid_sanitize_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P0_RELEASE_IDENTITY_EXPORTS_AFTERREQ_V1" not in s:
    raise SystemExit("[ERR] marker V1 not found (apply v1/v2 first)")

# 1) inject sanitize helper + release_ts_file into __vsp_release_meta()
# Find the meta = { ... } block inside __vsp_release_meta
# We'll add a helper def just before meta = { ... } and add key "release_ts_file"
pat_meta = r"(def __vsp_release_meta\(\):.*?)(meta\s*=\s*\{\s*\n)(\s*\"release_ts\"\s*:\s*rel_ts,.*?\n\s*\})"
m = re.search(pat_meta, s, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot locate __vsp_release_meta meta dict")

prefix = m.group(1)
meta_start = m.group(2)
meta_body = m.group(3)

# Add helper + rel_ts_file compute right before meta = {
inject = r'''
    def __vsp_sanitize_ts_for_filename(ts: str) -> str:
        # make ts safe for filenames across OS/tools
        t = (ts or "").strip()
        if not t:
            return ""
        # common transforms
        t = t.replace("T", "_").replace(":", "").replace("Z", "z")
        # normalize timezone like +07:00 -> p0700
        t = t.replace("+", "p").replace("-", "m")
        t = re.sub(r"[^0-9A-Za-z._-]+", "", t)
        return t

    rel_ts_file = __vsp_sanitize_ts_for_filename(rel_ts)
'''
# Insert inject just before meta = {
new_prefix = prefix
if "__vsp_sanitize_ts_for_filename" not in prefix:
    new_prefix = prefix + inject

# Add release_ts_file into dict (after release_ts)
if '"release_ts_file"' not in meta_body:
    meta_body = meta_body.replace('"release_ts": rel_ts,', '"release_ts": rel_ts,\n        "release_ts_file": rel_ts_file,', 1)

s = s[:m.start()] + new_prefix + meta_start + meta_body + s[m.end():]

# 2) Update __vsp_suffix(meta) to prefer release_ts_file for filenames
pat_suffix = r"def __vsp_suffix\(meta\):\s*.*?return f\"_rel-\{ts\}_sha-\{sha12\}\""
m2 = re.search(pat_suffix, s, flags=re.S)
if not m2:
    raise SystemExit("[ERR] cannot locate __vsp_suffix")

suffix_new = r'''def __vsp_suffix(meta):
    # prefer sanitized ts for filenames
    ts_raw = (meta.get("release_ts") or "").strip()
    ts_file = (meta.get("release_ts_file") or "").strip()
    ts = ts_file or ts_raw
    sha12 = meta.get("release_sha12") or "unknown"
    if ts.startswith("norel-"):
        return f"_{ts}_sha-{sha12}"
    return f"_rel-{ts}_sha-{sha12}"'''

s = s[:m2.start()] + suffix_new + s[m2.end():]

p.write_text(s, encoding="utf-8")
print("[OK] sanitized filename timestamp (release_ts_file) enabled")
PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] v3 sanitize applied."
