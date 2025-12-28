#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_exportrel_${TS}"
echo "[BACKUP] ${APP}.bak_exportrel_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_EXPORT_FILENAME_WITH_RELEASE_V1"
if marker in s:
    print("[OK] already present:", marker)
    raise SystemExit(0)

# Heuristic: patch inside the commercial export handler if present
# We look for def api_vsp_run_export_v3_commercial_real_v1( ... ):
m = re.search(r'^\s*def\s+(api_vsp_run_export_v3_commercial_real_v1)\s*\([^)]*\)\s*:\s*$', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find export handler: api_vsp_run_export_v3_commercial_real_v1")

fn_name = m.group(1)
start = m.start()
# find end of function block roughly: next def at same indent
rest = s[m.end():]
m2 = re.search(r'^\s*def\s+\w+\s*\([^)]*\)\s*:\s*$', rest, flags=re.M)
end = m.end() + (m2.start() if m2 else len(rest))

blk = s[start:end]

# Ensure we can read release_latest from server-side:
# We'll add a helper to load release json and build a suffix.
inject = r'''
    # ===================== {MARKER} =====================
    # Add release metadata to export filename (CSV/TGZ/HTML) for audit/demo clarity
    # Source: /api/vsp/release_latest OR out_ci/releases/release_latest.json
    # ====================================================
    def _vsp_load_release_meta():
        try:
            # try common release json location from UI project root
            from pathlib import Path as _Path
            root = _Path(__file__).resolve().parent
            cand = root / "out_ci" / "releases" / "release_latest.json"
            if cand.exists():
                import json
                j = json.loads(cand.read_text(encoding="utf-8", errors="replace"))
            else:
                j = {}
            def pick(*ks):
                for k in ks:
                    if k in j and str(j[k]).strip():
                        return str(j[k]).strip()
                    # case-insensitive
                    for kk in list(j.keys()):
                        if str(kk).lower() == str(k).lower() and str(j[kk]).strip():
                            return str(j[kk]).strip()
                return ""
            ts = pick("ts","timestamp","built_at","created_at")
            sha = pick("sha","sha256","git_sha","commit","commit_sha")
            pkg = pick("pkg_name","package_name","name","filename","PACKAGE")
            if not pkg:
                # fallback derive from url/path fields
                u = pick("pkg_url","package_url","download_url","url","href","pkg","package","path","tgz","tgz_path","pkg_path","package_path")
                if u:
                    pkg = u.split("/")[-1]
            sha12 = (sha[:12] if sha else "")
            pkg_base = re.sub(r'[^A-Za-z0-9._-]+','_', pkg)[:60] if pkg else ""
            ts_s = re.sub(r'[^0-9A-Za-z._-]+','_', ts)[:32] if ts else ""
            return {"ts": ts_s, "sha12": sha12, "pkg": pkg_base}
        except Exception:
            return {"ts":"", "sha12":"", "pkg":""}

    def _vsp_add_release_to_filename(base_name: str, ext: str):
        meta = _vsp_load_release_meta()
        parts = []
        if meta.get("pkg"): parts.append("UI_" + meta["pkg"])
        if meta.get("sha12"): parts.append(meta["sha12"])
        if meta.get("ts"): parts.append(meta["ts"])
        suf = ("__" + "__".join(parts)) if parts else ""
        safe_base = re.sub(r'[^A-Za-z0-9._-]+','_', base_name)[:90]
        return f"{safe_base}{suf}.{ext}"
    # ===================== /{MARKER} =====================
'''.replace("{MARKER}", marker)

# inject helper near top of function block (after def line)
lines = blk.splitlines(True)
# find first non-empty after def line
ins_i = 1
for i in range(1, min(len(lines), 30)):
    if lines[i].strip():
        ins_i = i
        break
blk2 = "".join(lines[:ins_i]) + inject + "".join(lines[ins_i:])

# Now patch Content-Disposition filename assignments
# Common patterns:
#   filename = f"...{rid}....tgz"
#   resp.headers["Content-Disposition"] = f'attachment; filename="{name}"'
# We'll add a minimal hook: if variable "rid" exists and ext known.
# Replace explicit filename="something.tgz" with computed name when possible.
blk2, n1 = re.subn(
    r'(Content-Disposition"\]\s*=\s*f?[\'"]attachment;\s*filename=\")([^"\n]+)\.(tgz|csv|html)([\'"])',
    r'\1{_vsp_add_release_to_filename("VSP_EXPORT_"+str(rid), "\3")}\4',
    blk2
)

# If no direct header string, patch lines that set a variable 'download_name' or 'name'
blk2, n2 = re.subn(
    r'^(?P<ind>\s*)(download_name|fname|name)\s*=\s*f?[\'"](?P<base>[^\'"]+)\.(tgz|csv|html)[\'"]\s*$',
    r'\g<ind>\2 = _vsp_add_release_to_filename("VSP_EXPORT_"+str(rid), "\4")',
    blk2,
    flags=re.M
)

# If nothing matched, we still keep helper; user can extend later.
print(f"[OK] patched export handler {fn_name}: header_subs={n1}, name_subs={n2}")

s2 = s[:start] + blk2 + s[end:]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1
echo "[DONE] export filename release metadata patch applied"
