#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4853_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl; need grep
command -v sudo >/dev/null 2>&1 || true

[ -f "$W" ] || { echo "[ERR] missing $W" | tee -a "$OUT/log.txt"; exit 2; }
cp -f "$W" "$OUT/${W}.bak_before_${TS}"
echo "[OK] backup => $OUT/${W}.bak_before_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P4853_WSGI_RUNS3_ITEMS_ALIAS_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# We will append a safe wrapper at EOF.
# It assumes `application` exists as a WSGI callable.
# Wrapper captures status+headers, buffers body, and rewrites JSON for /api/vsp/runs_v3.

block = r'''
# --- VSP_P4853_WSGI_RUNS3_ITEMS_ALIAS_V1 ---
def _vsp_p4853__wrap_wsgi_application(_orig_app):
    import json
    def _app(environ, start_response):
        try:
            path = environ.get("PATH_INFO","") or ""
            # Only touch runs_v3
            if path != "/api/vsp/runs_v3":
                return _orig_app(environ, start_response)

            captured = {"status": None, "headers": None}
            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers) if headers else []
                return start_response(status, headers, exc_info)

            body_iter = _orig_app(environ, _sr)

            # Buffer body (small response; safe)
            chunks = []
            for c in body_iter:
                if c:
                    chunks.append(c)
            if hasattr(body_iter, "close"):
                try: body_iter.close()
                except Exception: pass

            raw = b"".join(chunks) if chunks else b""
            hdrs = captured["headers"] or []
            # Ensure marker header always present for audit
            hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "x-vsp-p4853-runs3"]
            hdrs.append(("X-VSP-P4853-RUNS3", "1"))

            ct = ""
            for k,v in hdrs:
                if k.lower() == "content-type":
                    ct = v or ""
                    break

            if ("application/json" not in (ct or "").lower()) or (not raw.strip()):
                # replay original (but with marker header)
                def _sr2(status, headers, exc_info=None):
                    # merge: replace headers with hdrs but keep status
                    return start_response(status, hdrs, exc_info)
                _sr2(captured["status"] or "200 OK", hdrs)
                return [raw]

            try:
                obj = json.loads(raw.decode("utf-8", errors="replace"))
            except Exception:
                hdrs[-1] = ("X-VSP-P4853-RUNS3", "ERR_JSON")
                def _sr2(status, headers, exc_info=None):
                    return start_response(status, hdrs, exc_info)
                _sr2(captured["status"] or "200 OK", hdrs)
                return [raw]

            if isinstance(obj, dict) and ("items" not in obj) and isinstance(obj.get("runs"), list):
                obj["items"] = obj.get("runs") or []
                hdrs[-1] = ("X-VSP-P4853-RUNS3", "2")  # injected
                if "total" not in obj:
                    obj["total"] = len(obj["items"])
                new_raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
                # Fix content-length
                hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "content-length"]
                hdrs.append(("Content-Length", str(len(new_raw))))
                def _sr2(status, headers, exc_info=None):
                    return start_response(status, hdrs, exc_info)
                _sr2(captured["status"] or "200 OK", hdrs)
                return [new_raw]

            # No change needed, but keep marker header
            hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "content-length"]
            hdrs.append(("Content-Length", str(len(raw))))
            def _sr2(status, headers, exc_info=None):
                return start_response(status, hdrs, exc_info)
            _sr2(captured["status"] or "200 OK", hdrs)
            return [raw]

        except Exception:
            # fallback: never break pipeline
            return _orig_app(environ, start_response)
    return _app

try:
    application  # noqa: F401
    _vsp_p4853__orig_application = application
    application = _vsp_p4853__wrap_wsgi_application(_vsp_p4853__orig_application)
except Exception:
    pass
# --- end VSP_P4853_WSGI_RUNS3_ITEMS_ALIAS_V1 ---
'''

p.write_text(s + ("\n" if not s.endswith("\n") else "") + block, encoding="utf-8")
print("[OK] appended WSGI wrapper to wsgi_vsp_ui_gateway.py")
PY

python3 -m py_compile "$W" >/dev/null 2>&1 || {
  echo "[ERR] py_compile failed; restoring backup" | tee -a "$OUT/log.txt"
  cp -f "$OUT/${W}.bak_before_${TS}" "$W"
  exit 2
}
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then sudo systemctl restart "$SVC"; else systemctl restart "$SVC"; fi
systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "== [VERIFY] header marker + items ==" | tee -a "$OUT/log.txt"
HDR="$OUT/hdr.txt"; BODY="$OUT/body.json"
URL="$BASE/api/vsp/runs_v3?limit=5&include_ci=1"
curl -sS -D "$HDR" -o "$BODY" "$URL"

echo "-- header marker --" | tee -a "$OUT/log.txt"
grep -i "x-vsp-p4853-runs3" -n "$HDR" | tee -a "$OUT/log.txt" || true

python3 - <<PY | tee -a "$OUT/log.txt"
import json, pathlib
p = pathlib.Path("$BODY")
j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "items_len=", (len(j["items"]) if isinstance(j.get("items"), list) else "NA"))
print("runs_type=", type(j.get("runs")).__name__, "runs_len=", (len(j["runs"]) if isinstance(j.get("runs"), list) else "NA"))
print("total=", j.get("total"))
PY

echo "[OK] P4853 done. Close /c/runs tab, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log => $OUT/log.txt"
