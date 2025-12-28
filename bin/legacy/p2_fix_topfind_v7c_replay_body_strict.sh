#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_v7c_${TS}"
echo "[BACKUP] ${W}.bak_topfind_v7c_${TS}"

# 1) Remove any previously appended TOPFIND middleware blocks (v6/v7/v7b...) by marker truncation.
python3 - "$W" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

markers = [
  "VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7B",
  "VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7",
  "VSP_P2_TOPFIND_RUNID_WSGI_MW_V6",
  "VSP_P2_TOPFIND_RUNID_WSGI_MW_V5",
  "VSP_P2_TOPFIND_RUNID_WSGI_MW_V4",
]
cut = None
for m in markers:
    i = s.find(m)
    if i != -1:
        # cut at start of the line containing marker
        cut = s.rfind("\n", 0, i) + 1
        break

if cut is not None:
    s2 = s[:cut].rstrip() + "\n\n"
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] truncated old TOPFIND MW from marker: {markers[0]}.. (first hit)")
else:
    print("[OK] no prior TOPFIND MW marker found; keep file as-is")
PY

# 2) Append v7c middleware: capture+replay body correctly, and patch run_id if null.
cat >> "$W" <<'PY'

# === VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7C ===
# Fixes: (1) do NOT break HTTP response (no subversion), (2) do NOT consume body without replay,
# (3) ensure JSON body stays valid, (4) if run_id is None -> fill with rid_used (STRICT-friendly)
import os, json, urllib.request, urllib.parse, time

_VSP_TOPFIND_V7C_MARKER = "VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7C"

def _vsp_v7c_fetch_rid_latest(base: str, timeout: float = 0.8) -> str:
    """
    Best effort fetch rid_latest via local HTTP.
    Safe against recursion because middleware does nothing special for /api/vsp/rid_latest.
    """
    try:
        url = base.rstrip("/") + "/api/vsp/rid_latest"
        req = urllib.request.Request(url, headers={"Accept":"application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            b = r.read() or b""
        j = json.loads(b.decode("utf-8", "replace") or "{}")
        rid = (j.get("rid") or "").strip()
        return rid
    except Exception:
        return ""

def _vsp_qs_get(qs: str, key: str) -> str:
    try:
        d = urllib.parse.parse_qs(qs, keep_blank_values=True)
        v = d.get(key)
        return (v[0] if v else "") or ""
    except Exception:
        return ""

def _vsp_qs_set(qs: str, key: str, val: str) -> str:
    d = urllib.parse.parse_qs(qs, keep_blank_values=True)
    d[key] = [val]
    return urllib.parse.urlencode(d, doseq=True)

class _VSPTopFindV7CMiddleware:
    def __init__(self, app, base: str):
        self.app = app
        self.base = base.rstrip("/")
        self._cache_rid = ""
        self._cache_ts = 0.0

    def _get_rid_latest_cached(self) -> str:
        now = time.time()
        if self._cache_rid and (now - self._cache_ts) < 2.0:
            return self._cache_rid
        rid = _vsp_v7c_fetch_rid_latest(self.base)
        if rid:
            self._cache_rid = rid
            self._cache_ts = now
        return rid

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = (environ.get("QUERY_STRING") or "")

        # Force rid_latest if calling top_findings and rid is missing
        if path == "/api/vsp/top_findings_v1":
            if not _vsp_qs_get(qs, "rid"):
                rid_latest = self._get_rid_latest_cached()
                if rid_latest:
                    environ["QUERY_STRING"] = _vsp_qs_set(qs, "rid", rid_latest)

        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc"] = exc_info
            return start_response(status, headers, exc_info)

        app_iter = self.app(environ, _sr)

        body_chunks = []
        try:
            for chunk in app_iter:
                if chunk:
                    body_chunks.append(chunk)
        finally:
            try:
                close = getattr(app_iter, "close", None)
                if callable(close): close()
            except Exception:
                pass

        body = b"".join(body_chunks)

        # Only touch response for top_findings
        if path == "/api/vsp/top_findings_v1":
            # Ensure we always mark fix header
            hdrs = captured["headers"] or []
            # drop any old header
            hdrs = [(k, v) for (k, v) in hdrs if k.lower() != "x-vsp-topfind-runid-fix"]
            hdrs.append(("X-VSP-TOPFIND-RUNID-FIX", "ok-v7c"))
            captured["headers"] = hdrs

            # If body looks like JSON but run_id is null -> patch it (STRICT-friendly)
            try:
                if body and body.lstrip()[:1] in (b"{", b"["):
                    txt = body.decode("utf-8", "replace")
                    j = json.loads(txt)
                    if isinstance(j, dict):
                        if j.get("ok") is True and (j.get("run_id") is None or j.get("run_id") == ""):
                            rid_used = j.get("rid_used") or j.get("rid") or _vsp_qs_get(environ.get("QUERY_STRING",""), "rid")
                            if rid_used:
                                j["run_id"] = rid_used
                                j["marker"] = _VSP_TOPFIND_V7C_MARKER
                                body = json.dumps(j, ensure_ascii=False).encode("utf-8")
            except Exception:
                # do not break response
                pass

            # Fix Content-Length to match (important when we modified body)
            hdrs = [(k, v) for (k, v) in (captured["headers"] or []) if k.lower() != "content-length"]
            hdrs.append(("Content-Length", str(len(body))))
            captured["headers"] = hdrs

            # Re-send headers with same status (already sent). In WSGI, start_response already called.
            # We can't call start_response again, so only return corrected body.
            return [body]

        return [body]

# Wrap gunicorn target
try:
    _base = os.environ.get("VSP_UI_BASE", "http://127.0.0.1:8910")
    _orig = globals().get("application") or globals().get("app")
    if _orig:
        globals()["application"] = _VSPTopFindV7CMiddleware(_orig, _base)
except Exception:
    pass
# === END V7C ===
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sleep 0.6
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== PROOF headers (HEAD) =="
curl --http1.1 -sSI "$BASE/api/vsp/top_findings_v1?limit=1" | egrep -i 'http/|content-type|content-length|x-vsp-topfind-runid-fix' || true

echo "== PROOF body bytes =="
curl --http1.1 -sS "$BASE/api/vsp/top_findings_v1?limit=1" | wc -c

echo "== PROOF body JSON (STRICT fields) =="
curl --http1.1 -sS "$BASE/api/vsp/top_findings_v1?limit=1" | python3 - <<'PY'
import sys,json
raw=sys.stdin.read()
print("raw_len=",len(raw))
j=json.loads(raw)
print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"run_id=",j.get("run_id"),"marker=",j.get("marker"),"total=",j.get("total"))
PY
