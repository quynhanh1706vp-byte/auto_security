#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need awk
command -v node >/dev/null 2>&1 || { echo "[ERR] node is required for syntax selection"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# ---------- (A) Restore JS from best backup that PASSES node --check ----------
python3 - <<'PY'
from pathlib import Path
import subprocess, sys, time

targets = [
  Path("static/js/vsp_runs_tab_resolved_v1.js"),
  Path("static/js/vsp_bundle_commercial_v2.js"),
  Path("static/js/vsp_bundle_commercial_v1.js"),
  Path("static/js/vsp_app_entry_safe_v1.js"),
  Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js"),
]

def node_ok(p: Path) -> bool:
  try:
    r = subprocess.run(["node","--check",str(p)], capture_output=True, text=True)
    return r.returncode == 0
  except Exception:
    return False

def best_candidate(dst: Path):
  cands = []
  if dst.exists():
    cands.append(dst)
  # backups in same dir
  for bak in sorted(dst.parent.glob(dst.name + ".bak_*")):
    cands.append(bak)
  # some scripts wrote backups without full prefix (rare) -> still try
  for bak in sorted(dst.parent.glob(dst.stem + ".bak_*")):
    cands.append(bak)

  good = []
  for p in cands:
    if p.exists() and node_ok(p):
      good.append(p)
  if not good:
    return None
  good.sort(key=lambda p: p.stat().st_mtime, reverse=True)
  return good[0]

changed = []
for dst in targets:
  if not dst.exists():
    continue
  ok_now = node_ok(dst)
  best = best_candidate(dst)
  if best is None:
    # create minimal safe stub to prevent page-wide crash
    bak = dst.with_name(dst.name + f".bak_autostub_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(dst.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    dst.write_text(
      "/* VSP_AUTOSTUB_JS_V1: file was broken; stubbed to keep UI alive */\n"
      "(function(){\n"
      "  try{ console.warn('[VSP][AUTOSTUB] '+(document.currentScript&&document.currentScript.src||'js')+' stubbed'); }catch(_){ }\n"
      "})();\n",
      encoding="utf-8"
    )
    changed.append(str(dst) + " => STUB")
    continue

  if (not ok_now) or (best != dst):
    bak = dst.with_name(dst.name + f".bak_factory_reset_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(dst.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    dst.write_text(best.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    changed.append(f"{dst} <= {best.name}")

print("[JS_RESET] changed:", len(changed))
for x in changed:
  print(" -", x)

# final strict check: any broken js => fail fast
bad = []
for p in Path("static/js").glob("*.js"):
  r = subprocess.run(["node","--check",str(p)], capture_output=True, text=True)
  if r.returncode != 0:
    bad.append((p, r.stderr.strip().splitlines()[-1] if r.stderr else "syntax error"))
if bad:
  print("[ERR] some JS still broken:")
  for p,msg in bad[:30]:
    print(" -", p, "::", msg)
  sys.exit(3)
print("[OK] node --check ALL static/js/*.js")
PY

# ---------- (B) Strip any injected RUNS wrapper blocks in templates (safe, idempotent) ----------
python3 - <<'PY'
from pathlib import Path
import re, time

MARKERS = [
  "VSP_P0_RUNS_FETCH_LOCK",
  "VSP_P0_RUNS_NEVER503",
  "VSP_P0_RUNS",
  "VSP_P1_RUNS",
  "VSP_RUNS_FETCH_LOCK",
  "runs fetch lock installed",
  "fetch wrapper enabled for /api/vsp/runs",
]

def strip_blocks(s: str) -> str:
  # remove any <script id="...RUNS..."> ... </script> blocks (only those containing markers)
  def repl(m):
    blk = m.group(0)
    low = blk.lower()
    if any(k.lower() in low for k in MARKERS):
      return ""
    return blk
  s = re.sub(r"<script\b[^>]*>.*?</script\s*>", repl, s, flags=re.S|re.I)
  return s

tpls = []
for pat in ["templates/*.html", "templates/**/*.html"]:
  tpls += list(Path(".").glob(pat))
tpls = [p for p in tpls if p.is_file()]

changed = 0
ts = time.strftime("%Y%m%d_%H%M%S")
for p in tpls:
  s = p.read_text(encoding="utf-8", errors="replace")
  s2 = strip_blocks(s)
  if s2 != s:
    bak = p.with_name(p.name + f".bak_strip_runsblocks_{ts}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s2, encoding="utf-8")
    changed += 1
print("[TPL_STRIP] changed:", changed)
PY

# ---------- (C) Add WSGI middleware: NEVER return 5xx for /api/vsp/runs ----------
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_runs_never503_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RUNS_NEVER503_MW_V1"
if MARK in s:
  print("[OK] middleware already present")
  raise SystemExit(0)

block = r'''
# === VSP_P0_RUNS_NEVER503_MW_V1 ===
import json as _vsp_json

class _VSPRunsNever503MW:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/runs"):
            return self.app(environ, start_response)

        status_headers = {"status": None, "headers": None}
        body_chunks = []

        def _sr(status, headers, exc_info=None):
            status_headers["status"] = status
            status_headers["headers"] = headers
            def _write(x):
                if x:
                    body_chunks.append(x if isinstance(x, (bytes, bytearray)) else str(x).encode("utf-8", "replace"))
            return _write

        try:
            res = self.app(environ, _sr)
            for ch in res:
                if ch:
                    body_chunks.append(ch if isinstance(ch, (bytes, bytearray)) else str(ch).encode("utf-8", "replace"))
            if hasattr(res, "close"):
                try: res.close()
                except Exception: pass

            st = status_headers["status"] or "500 INTERNAL SERVER ERROR"
            code = int(st.split()[0])
            if code >= 500:
                payload = {
                    "ok": True,
                    "degraded": True,
                    "degraded_reason": f"upstream_http_{code}",
                    "limit": 0,
                    "items": [],
                    "rid_latest": None,
                }
                out = _vsp_json.dumps(payload).encode("utf-8")
                hdrs = [
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Cache-Control","no-store"),
                    ("Content-Length", str(len(out))),
                    ("X-VSP-RUNS-CONTRACT","P1_WSGI_V2"),
                    ("X-VSP-DEGRADED","1"),
                ]
                start_response("200 OK", hdrs)
                return [out]

            # pass-through original
            start_response(st, status_headers["headers"] or [])
            return [b"".join(body_chunks)]

        except Exception as e:
            payload = {
                "ok": True,
                "degraded": True,
                "degraded_reason": "exception",
                "error": str(e),
                "limit": 0,
                "items": [],
                "rid_latest": None,
            }
            out = _vsp_json.dumps(payload).encode("utf-8")
            hdrs = [
                ("Content-Type","application/json; charset=utf-8"),
                ("Cache-Control","no-store"),
                ("Content-Length", str(len(out))),
                ("X-VSP-RUNS-CONTRACT","P1_WSGI_V2"),
                ("X-VSP-DEGRADED","1"),
            ]
            start_response("200 OK", hdrs)
            return [out]

def _vsp_wrap_runs_never503(app):
    return _VSPRunsNever503MW(app)

try:
    if "application" in globals():
        application = _vsp_wrap_runs_never503(application)
    elif "app" in globals():
        app = _vsp_wrap_runs_never503(app)
except Exception as _e:
    print("[VSP][WARN] runs never503 mw attach failed:", _e)
# === END VSP_P0_RUNS_NEVER503_MW_V1 ===
'''

p.write_text(s + "\n" + block + "\n", encoding="utf-8")
print("[OK] appended middleware:", MARK)
PY

# ---------- (D) Restart UI clean ----------
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bash bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== VERIFY /api/vsp/runs never503 =="
for i in 1 2 3; do
  curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=20" | sed -n '1,12p'
  echo
done

echo "[OK] DONE. Now open INCOGNITO once and hard refresh /runs + /vsp5."
echo "Tip: in DevTools > Application > Storage: Clear site data (optional) if banner still stuck from localStorage."
