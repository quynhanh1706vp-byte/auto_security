#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4853c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl; need sed; need head; need grep
command -v sudo >/dev/null 2>&1 || true

[ -f "$W" ] || { echo "[ERR] missing $W" | tee -a "$OUT/log.txt"; exit 2; }
cp -f "$W" "$OUT/${W}.bak_before_${TS}"
echo "[OK] backup => $OUT/${W}.bak_before_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove old buggy P4853 block if present
s2 = re.sub(
    r'\n# --- VSP_P4853_WSGI_RUNS3_ITEMS_ALIAS_V1 ---.*?# --- end VSP_P4853_WSGI_RUNS3_ITEMS_ALIAS_V1 ---\n',
    '\n',
    s,
    flags=re.S
)

MARK = "VSP_P4853C_WSGI_RUNS3_ITEMS_ALIAS_V1"
if MARK in s2:
    print("[OK] already has P4853C block; no append")
    p.write_text(s2, encoding="utf-8")
    raise SystemExit(0)

block = r'''
# --- VSP_P4853C_WSGI_RUNS3_ITEMS_ALIAS_V1 ---
def _vsp_p4853c__wrap_wsgi_application(_orig_app):
    import json
    def _app(environ, start_response):
        path = environ.get("PATH_INFO", "") or ""
        # Only touch runs_v3; otherwise pass-through
        if path != "/api/vsp/runs_v3":
            return _orig_app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None, "write": None}

        # IMPORTANT: do NOT call the real start_response here (avoid double call)
        def _capture_start_response(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            # Return a dummy "write" callable (rarely used)
            def _write(_data):  # pragma: no cover
                # If app uses "write", we ignore; we still buffer iterable below.
                return None
            captured["write"] = _write
            return _write

        body_iter = _orig_app(environ, _capture_start_response)

        chunks = []
        try:
            for c in body_iter:
                if c:
                    chunks.append(c)
        finally:
            if hasattr(body_iter, "close"):
                try: body_iter.close()
                except Exception: pass

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        raw = b"".join(chunks) if chunks else b""

        # Always attach audit marker
        headers = [(k,v) for (k,v) in headers if k.lower() != "x-vsp-p4853c-runs3"]
        headers.append(("X-VSP-P4853C-RUNS3", "1"))

        # Determine content-type
        ct = ""
        for k,v in headers:
            if k.lower() == "content-type":
                ct = v or ""
                break

        # If not JSON or empty => just return original with marker
        if ("application/json" not in (ct or "").lower()) or (not raw.strip()):
            # fix content-length
            headers = [(k,v) for (k,v) in headers if k.lower() != "content-length"]
            headers.append(("Content-Length", str(len(raw))))
            start_response(status, headers, captured["exc"])
            return [raw]

        # Try parse & inject items
        try:
            obj = json.loads(raw.decode("utf-8", errors="replace"))
        except Exception:
            headers[-1] = ("X-VSP-P4853C-RUNS3", "ERR_JSON")
            headers = [(k,v) for (k,v) in headers if k.lower() != "content-length"]
            headers.append(("Content-Length", str(len(raw))))
            start_response(status, headers, captured["exc"])
            return [raw]

        changed = False
        if isinstance(obj, dict) and ("items" not in obj) and isinstance(obj.get("runs"), list):
            obj["items"] = obj.get("runs") or []
            if "total" not in obj:
                obj["total"] = len(obj["items"])
            changed = True

        if changed:
            headers[-1] = ("X-VSP-P4853C-RUNS3", "2")  # injected
            new_raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            headers = [(k,v) for (k,v) in headers if k.lower() != "content-length"]
            headers.append(("Content-Length", str(len(new_raw))))
            start_response(status, headers, captured["exc"])
            return [new_raw]

        # no change
        headers = [(k,v) for (k,v) in headers if k.lower() != "content-length"]
        headers.append(("Content-Length", str(len(raw))))
        start_response(status, headers, captured["exc"])
        return [raw]

    return _app

try:
    application  # exists?
    _vsp_p4853c__orig_application = application
    application = _vsp_p4853c__wrap_wsgi_application(_vsp_p4853c__orig_application)
except Exception:
    pass
# --- end VSP_P4853C_WSGI_RUNS3_ITEMS_ALIAS_V1 ---
'''

p.write_text(s2 + ("\n" if not s2.endswith("\n") else "") + block, encoding="utf-8")
print("[OK] replaced old P4853 (if any) and appended P4853C")
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

echo "== [VERIFY] status+headers+body preview ==" | tee -a "$OUT/log.txt"
HDR="$OUT/hdr.txt"; BODY="$OUT/body.bin"
URL="$BASE/api/vsp/runs_v3?limit=5&include_ci=1"
curl -sS -D "$HDR" -o "$BODY" "$URL"

echo "-- status line --" | tee -a "$OUT/log.txt"
sed -n '1,5p' "$HDR" | tee -a "$OUT/log.txt"

echo "-- marker headers --" | tee -a "$OUT/log.txt"
grep -inE "x-vsp-p4853c-runs3|content-type|content-length" "$HDR" | tee -a "$OUT/log.txt" || true

echo "-- body preview (first 200 bytes) --" | tee -a "$OUT/log.txt"
python3 - <<PY | tee -a "$OUT/log.txt"
import pathlib
b = pathlib.Path("$BODY").read_bytes()
print("len=", len(b))
print(b[:200])
PY

echo "-- json keys check (only if json) --" | tee -a "$OUT/log.txt"
python3 - <<PY | tee -a "$OUT/log.txt"
import pathlib, json
b = pathlib.Path("$BODY").read_bytes()
try:
    j = json.loads(b.decode("utf-8", errors="replace"))
    print("keys=", sorted(j.keys()))
    print("items_type=", type(j.get("items")).__name__, "items_len=", (len(j["items"]) if isinstance(j.get("items"), list) else "NA"))
    print("runs_type=", type(j.get("runs")).__name__, "runs_len=", (len(j["runs"]) if isinstance(j.get("runs"), list) else "NA"))
    print("total=", j.get("total"))
except Exception as e:
    print("NOT_JSON:", type(e).__name__, str(e)[:120])
PY

echo "[OK] P4853C done. Close /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log => $OUT/log.txt"
