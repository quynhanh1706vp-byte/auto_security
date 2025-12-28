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
cp -f "$WSGI" "${WSGI}.bak_relid_afterreq_${TS}"
echo "[BACKUP] ${WSGI}.bak_relid_afterreq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RELEASE_IDENTITY_EXPORTS_AFTERREQ_V1"
if MARK in s:
    print("[OK] marker already present:", MARK)
    raise SystemExit(0)

block = r'''
# ===================== VSP_P0_RELEASE_IDENTITY_EXPORTS_AFTERREQ_V1 =====================
# P0: attach release identity headers + normalize export filenames with _rel-<ts>_sha-<12> (or _norel-... fallback)
try:
    from flask import request
except Exception:
    request = None

import os, json, time, re
from pathlib import Path

__vsp_rel_cache = {"t": 0.0, "meta": None}
__vsp_rel_cache_ttl = float(os.environ.get("VSP_RELEASE_CACHE_TTL", "5.0"))

def __vsp_now_ts():
    return time.strftime("%Y%m%d_%H%M%S", time.localtime())

def __vsp_pick_release_latest_json():
    # precedence: env -> common absolute -> relative
    envp = os.environ.get("VSP_RELEASE_LATEST_JSON")
    cands = []
    if envp:
        cands.append(envp)
    cands += [
        "/home/test/Data/SECURITY_BUNDLE/out_ci/releases/release_latest.json",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/release_latest.json",
        str(Path(".") / "out_ci" / "releases" / "release_latest.json"),
        str(Path(".") / "out" / "releases" / "release_latest.json"),
    ]
    for x in cands:
        try:
            xp = Path(x)
            if xp.is_file() and xp.stat().st_size > 0:
                return xp
        except Exception:
            pass
    return None

def __vsp_read_release_latest():
    rp = __vsp_pick_release_latest_json()
    if not rp:
        return None
    try:
        return json.loads(rp.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None

def __vsp_release_meta():
    # tiny cache to avoid IO per request
    now = time.time()
    if __vsp_rel_cache["meta"] is not None and (now - __vsp_rel_cache["t"]) < __vsp_rel_cache_ttl:
        return __vsp_rel_cache["meta"]

    j = __vsp_read_release_latest() or {}
    # accept several possible shapes
    rel_ts  = str(j.get("release_ts") or j.get("ts") or j.get("built_ts") or "").strip()
    rel_sha = str(j.get("release_sha") or j.get("sha") or j.get("git_sha") or j.get("commit") or "").strip()
    rel_pkg = str(j.get("release_pkg") or j.get("pkg") or j.get("package") or j.get("tgz") or "").strip()

    if rel_sha:
        rel_sha12 = re.sub(r"[^0-9a-fA-F]", "", rel_sha)[:12] or "unknown"
    else:
        rel_sha12 = "unknown"

    if not rel_ts:
        rel_ts = "norel-" + __vsp_now_ts()

    meta = {
        "release_ts": rel_ts,
        "release_sha": rel_sha,
        "release_sha12": rel_sha12,
        "release_pkg": rel_pkg or "-",
    }
    __vsp_rel_cache["t"] = now
    __vsp_rel_cache["meta"] = meta
    return meta

def __vsp_suffix(meta):
    # if meta["release_ts"] already has "norel-" prefix, keep consistent output:
    ts = meta.get("release_ts") or ""
    sha12 = meta.get("release_sha12") or "unknown"
    if ts.startswith("norel-"):
        return f"_{ts}_sha-{sha12}"
    return f"_rel-{ts}_sha-{sha12}"

def __vsp_rewrite_filename(fn, meta):
    if not fn:
        return fn
    # already stamped?
    if ("_rel-" in fn) or ("_norel-" in fn):
        return fn
    suf = __vsp_suffix(meta)

    # insert before extension (last dot), but keep .tar.gz style intact
    lower = fn.lower()
    if lower.endswith(".tar.gz"):
        base = fn[:-7]
        return base + suf + ".tar.gz"
    if "." in fn:
        base, ext = fn.rsplit(".", 1)
        return base + suf + "." + ext
    return fn + suf

def __vsp_parse_cd_filename(cd):
    # supports: filename="x"; filename=x; filename*=UTF-8''x
    if not cd:
        return None
    m = re.search(r'filename\*\s*=\s*UTF-8\'\'([^;]+)', cd, flags=re.I)
    if m:
        return m.group(1).strip().strip('"').strip("'")
    m = re.search(r'filename\s*=\s*"([^"]+)"', cd, flags=re.I)
    if m:
        return m.group(1)
    m = re.search(r'filename\s*=\s*([^;]+)', cd, flags=re.I)
    if m:
        return m.group(1).strip().strip('"').strip("'")
    return None

def __vsp_is_attachment(cd):
    return bool(cd) and ("attachment" in cd.lower()) and ("filename" in cd.lower())

def __vsp_after_request(resp):
    try:
        meta = __vsp_release_meta()
        # Headers for audit/build identity
        resp.headers.setdefault("X-VSP-RELEASE-TS", meta.get("release_ts", "-"))
        resp.headers.setdefault("X-VSP-RELEASE-SHA", meta.get("release_sha", ""))
        resp.headers.setdefault("X-VSP-RELEASE-PKG", meta.get("release_pkg", "-"))

        # Rewrite only when it's an attachment (export/download)
        cd = resp.headers.get("Content-Disposition", "")
        if __vsp_is_attachment(cd):
            fn = __vsp_parse_cd_filename(cd)
            newfn = __vsp_rewrite_filename(fn, meta)
            if newfn and newfn != fn:
                # normalize to a simple, consistent header
                resp.headers["Content-Disposition"] = f'attachment; filename="{newfn}"'
        return resp
    except Exception:
        return resp

# register hook safely (no decorator; works for app/application exports)
__vsp_app = globals().get("app") or globals().get("application")
if __vsp_app and hasattr(__vsp_app, "after_request"):
    if not getattr(__vsp_app, "__vsp_p0_relid_afterreq_v1", False):
        __vsp_app.after_request(__vsp_after_request)
        __vsp_app.__vsp_p0_relid_afterreq_v1 = True
# ===================== /VSP_P0_RELEASE_IDENTITY_EXPORTS_AFTERREQ_V1 =====================
'''

# Insert location: after the export head support block if present; else before __main__; else append
inserted = False
end_anchor = "===================== /VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C ====================="
i = s.find(end_anchor)
if i != -1:
    j = s.find("\n", i)
    if j == -1:
        j = len(s)
    s = s[:j+1] + block + "\n" + s[j+1:]
    inserted = True

if not inserted:
    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
    if m:
        s = s[:m.start()] + block + "\n\n" + s[m.start():]
        inserted = True

if not inserted:
    s = s.rstrip() + "\n\n" + block + "\n"
    inserted = True

p.write_text(s, encoding="utf-8")
print("[OK] inserted marker:", MARK)
PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart service (best-effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo
echo "== quick verify headers (pick ANY export endpoint you already have) =="
echo "Example (CSV): curl -sS -D- 'http://127.0.0.1:8910/api/vsp/<YOUR_EXPORT_ENDPOINT>?rid=<RID>' -o /dev/null | egrep -i 'content-disposition|x-vsp-release-'"
echo
echo "[DONE] P0 release identity after_request hook installed."
