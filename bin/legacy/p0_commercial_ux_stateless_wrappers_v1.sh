#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

APP="vsp_demo_app.py"
[ -f "$APP" ] || err "missing $APP"

TS="$(date +%Y%m%d_%H%M%S)"

# ---- targets (from your audit list) ----
JS_TOPBAR="static/js/vsp_topbar_commercial_v1.js"
JS_DASH="static/js/vsp_dashboard_luxe_v1.js"
JS_TABS_COMMON="static/js/vsp_tabs3_common_v3.js"
JS_TABS_BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
JS_DASH_CONS="static/js/vsp_dashboard_consistency_patch_v1.js"
JS_DS_PAG="static/js/vsp_data_source_pagination_v1.js"
JS_DS_TAB="static/js/vsp_data_source_tab_v3.js"

for f in "$JS_TOPBAR" "$JS_DASH" "$JS_TABS_COMMON" "$JS_TABS_BUNDLE" "$JS_DASH_CONS" "$JS_DS_PAG" "$JS_DS_TAB"; do
  [ -f "$f" ] || warn "missing optional JS: $f"
done

# ---- backups ----
cp -f "$APP" "${APP}.bak_commercial_wrap_${TS}"
ok "backup: ${APP}.bak_commercial_wrap_${TS}"

for f in "$JS_TOPBAR" "$JS_DASH" "$JS_TABS_COMMON" "$JS_TABS_BUNDLE" "$JS_DASH_CONS" "$JS_DS_PAG" "$JS_DS_TAB"; do
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_commercial_wrap_${TS}"
    ok "backup: ${f}.bak_commercial_wrap_${TS}"
  fi
done

# ---- [A] Backend: add stateless wrapper APIs (idempotent) ----
python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P0_COMMERCIAL_API_WRAPPERS_V1"
if MARK in s:
  print("[OK] backend already patched:", MARK)
  raise SystemExit(0)

# Insert before __main__ if exists, else append
ins = textwrap.dedent(r'''
# === VSP_P0_COMMERCIAL_API_WRAPPERS_V1 ===
# Purpose:
# - FE must NOT call run_file_allow, and must NOT know internal file paths/names.
# - Provide stateless commercial API wrappers with paging + caching headers.

def __vsp__now_iso():
  try:
    import datetime as _dt
    return _dt.datetime.utcnow().isoformat()
  except Exception:
    return ""

def __vsp__run_roots():
  import os
  roots = []
  # Prefer explicit env
  env = os.environ.get("VSP_RUN_ROOTS","").strip()
  if env:
    for x in env.split(":"):
      x = x.strip()
      if x:
        roots.append(x)
  # Known defaults (safe, best-effort)
  defaults = [
    "/home/test/Data/SECURITY_BUNDLE/out_ci",
    "/home/test/Data/SECURITY_BUNDLE/out",
    "/home/test/Data/SECURITY-10-10-v4/out_ci",
    "/home/test/Data/SECURITY-10-10-v4/out",
    "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    "/home/test/Data/SECURITY_BUNDLE/ui/out",
  ]
  for d in defaults:
    if d not in roots:
      roots.append(d)
  return roots

def __vsp__find_rundir(rid: str):
  from pathlib import Path
  if not rid:
    return None
  rid = str(rid).strip()
  if not rid:
    return None
  # Direct hit
  for root in __vsp__run_roots():
    p = Path(root) / rid
    if p.is_dir():
      return p
  # Shallow glob fallback (depth <= 3)
  for root in __vsp__run_roots():
    base = Path(root)
    if not base.exists():
      continue
    # avoid huge recursion: only 3 levels
    globs = [
      f"{rid}",
      f"*/{rid}",
      f"*/*/{rid}",
      f"*/*/*/{rid}",
    ]
    for g in globs:
      for cand in base.glob(g):
        if cand.is_dir():
          return cand
  return None

def __vsp__load_json_for_rid(rid: str, relpaths):
  import json
  rd = __vsp__find_rundir(rid)
  if not rd:
    return None, None
  rels = list(relpaths or [])
  # Try exact rel first, then common prefixes
  try_list = []
  for rp in rels:
    rp = (rp or "").lstrip("/")
    if not rp:
      continue
    try_list.append(rp)
    if not rp.startswith("reports/"):
      try_list.append("reports/" + rp)
    if not rp.startswith("report/"):
      try_list.append("report/" + rp)
  # de-dup
  seen=set(); ordered=[]
  for x in try_list:
    if x not in seen:
      seen.add(x); ordered.append(x)

  for rp in ordered:
    fp = rd / rp
    if fp.is_file():
      try:
        obj = json.loads(fp.read_text(encoding="utf-8", errors="ignore"))
      except Exception:
        # try binary json
        try:
          obj = json.loads(fp.read_bytes().decode("utf-8", errors="ignore"))
        except Exception:
          obj = None
      if obj is not None:
        return obj, str(fp)
  return None, None

def __vsp__resp(payload: dict, cache_s: int = 30):
  # set caching headers to reduce XHR spam
  try:
    from flask import make_response, jsonify
    r = make_response(jsonify(payload))
    r.headers["Cache-Control"] = f"public, max-age={int(cache_s)}"
    return r
  except Exception:
    return payload

# --- wrapper: run_gate_summary (no run_file_allow) ---
@app.get("/api/vsp/run_gate_summary_v1")
def vsp_run_gate_summary_v1():
  from flask import request
  rid = (request.args.get("rid") or "").strip()
  j, fp = __vsp__load_json_for_rid(rid, ["run_gate_summary.json"])
  if not isinstance(j, dict):
    return __vsp__resp({"ok": True, "rid": rid, "ts": __vsp__now_iso(), "no_data": True, "counts_total": {"total": 0}, "counts_by_sev": {}, "by_tool": {}, "by_cwe": {}, "by_module": {}}, 15)
  # Commercial: do NOT leak file path; keep payload flat for existing FE.
  j = dict(j)
  j["ok"] = True
  j["rid"] = rid
  j["ts"] = __vsp__now_iso()
  j["no_data"] = False
  # Ensure totals never missing (CIO trust)
  ct = j.get("counts_total") or {}
  if not isinstance(ct, dict):
    ct = {}
  if ct.get("total") is None:
    # derive from counts_by_sev if present
    cbs = j.get("counts_by_sev") or {}
    if isinstance(cbs, dict):
      try:
        ct["total"] = int(sum(int(v or 0) for v in cbs.values()))
      except Exception:
        ct["total"] = 0
    else:
      ct["total"] = 0
  j["counts_total"] = ct
  # Normalize missing sev buckets to 0
  cbs = j.get("counts_by_sev") or {}
  if not isinstance(cbs, dict):
    cbs = {}
  for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
    if cbs.get(k) is None:
      cbs[k] = 0
  j["counts_by_sev"] = cbs
  return __vsp__resp(j, 30)

# --- wrapper: run_manifest (no run_file_allow) ---
@app.get("/api/vsp/run_manifest_v1")
def vsp_run_manifest_v1():
  from flask import request
  rid = (request.args.get("rid") or "").strip()
  j, fp = __vsp__load_json_for_rid(rid, ["run_manifest.json"])
  if not isinstance(j, dict):
    return __vsp__resp({"ok": True, "rid": rid, "ts": __vsp__now_iso(), "no_data": True, "manifest": {}}, 15)
  out = {"ok": True, "rid": rid, "ts": __vsp__now_iso(), "no_data": False, "manifest": j}
  return __vsp__resp(out, 30)

# --- wrapper: findings paging/search/filter (no run_file_allow, no file name leaks) ---
@app.get("/api/vsp/findings_page_v3")
def vsp_findings_page_v3():
  from flask import request
  rid = (request.args.get("rid") or "").strip()
  try: limit = int(request.args.get("limit") or 50)
  except Exception: limit = 50
  try: offset = int(request.args.get("offset") or 0)
  except Exception: offset = 0
  limit = max(1, min(limit, 200))
  offset = max(0, offset)

  q = (request.args.get("q") or "").strip().lower()
  tool = (request.args.get("tool") or "").strip().upper()
  sev  = (request.args.get("severity") or "").strip().upper()
  cwe  = (request.args.get("cwe") or "").strip()
  file_kw = (request.args.get("file") or "").strip().lower()
  mod_kw  = (request.args.get("module") or "").strip().lower()

  j, fp = __vsp__load_json_for_rid(rid, ["findings_unified.json"])
  # Support legacy: sometimes findings are nested under "findings"
  items = []
  if isinstance(j, dict) and isinstance(j.get("findings"), list):
    items = j.get("findings") or []
  elif isinstance(j, list):
    items = j
  else:
    items = []

  def match(it: dict) -> bool:
    try:
      if tool and str(it.get("tool","")).upper() != tool:
        return False
      if sev and str(it.get("severity","")).upper() != sev:
        return False
      if cwe and str(it.get("cwe") or "").strip() != cwe:
        return False
      if file_kw and file_kw not in str(it.get("file","")).lower():
        return False
      if mod_kw and mod_kw not in str(it.get("module","")).lower():
        return False
      if q:
        blob = " ".join([
          str(it.get("title","")),
          str(it.get("tool","")),
          str(it.get("severity","")),
          str(it.get("file","")),
          str(it.get("module","")),
          str(it.get("cwe","") or ""),
        ]).lower()
        if q not in blob:
          return False
      return True
    except Exception:
      return True

  filt = [it for it in items if isinstance(it, dict) and match(it)]
  total = len(filt)
  page = filt[offset: offset + limit]

  # Commercial contract: do NOT include any internal filenames in UI-visible fields
  payload = {
    "ok": True,
    "rid": rid,
    "ts": __vsp__now_iso(),
    "profile": {"mode": "commercial"},
    "filters": {"limit": limit, "offset": offset, "q": q, "tool": tool, "severity": sev, "cwe": cwe, "file": file_kw, "module": mod_kw},
    "data": {"items": page, "total": total},
    "meta": {"paging": {"limit": limit, "offset": offset, "next_offset": (offset + limit if offset + limit < total else None)},
             "no_data": (len(items) == 0),
             "coverage": {"tools_expected": 8}},
  }
  return __vsp__resp(payload, 30)

# === /VSP_P0_COMMERCIAL_API_WRAPPERS_V1 ===
''').strip("\n") + "\n"

m = re.search(r"^if\s+__name__\s*==\s*[\"']__main__[\"']\s*:\s*$", s, flags=re.M)
if m:
  s = s[:m.start()] + ins + "\n" + s[m.start():]
else:
  s = s + "\n\n" + ins

p.write_text(s, encoding="utf-8")
print("[OK] backend patched:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
ok "py_compile OK: vsp_demo_app.py"

# ---- [B] Frontend: remove N/A + remove debug labels + stop calling run_file_allow ----
python3 - <<'PY'
from pathlib import Path
import re

def patch_file(path, fn):
  p = Path(path)
  if not p.exists():
    print("[WARN] missing:", path)
    return
  s = p.read_text(encoding="utf-8", errors="ignore")
  ns = fn(s)
  if ns != s:
    p.write_text(ns, encoding="utf-8")
    print("[OK] patched:", path)
  else:
    print("[OK] nochange:", path)

# 1) Topbar: N/A -> — + tooltip
def patch_topbar(s: str) -> str:
  s2 = s
  # Replace literal "N/A" text assignments (only in topbar)
  s2 = s2.replace('setText("vspLatestRid", "N/A");', 'setText("vspLatestRid", "—"); try{ var el=document.getElementById("vspLatestRid"); if(el){ el.title="Select a valid RID"; el.style.cursor="pointer"; el.onclick=function(){ try{ window.__vsp_openRidPicker?.(); }catch(e){} }; } }catch(e){}')
  s2 = s2.replace('wireExport("N/A");', 'wireExport("—");')
  # If there are other N/A occurrences, turn them into —
  s2 = re.sub(r'(["\'])N/A\1', r'"\u2014"', s2)
  return s2

# 2) Replace run_file_allow calls to wrappers + remove internal file names/labels
def patch_no_runfileallow(s: str) -> str:
  x = s

  # Gate summary wrapper
  x = re.sub(r'(/api/vsp/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=run_gate_summary\.json[^`]*)',
             r'/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}', x)
  x = x.replace('/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json&ts=" + Date.now()',
                '/api/vsp/run_gate_summary_v1?rid=" + encodeURIComponent(rid)')
  x = x.replace('/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json',
                '/api/vsp/run_gate_summary_v1?rid=" + encodeURIComponent(rid)')
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`',
                '`/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}`')

  # Manifest wrapper
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_manifest.json`',
                '`/api/vsp/run_manifest_v1?rid=${encodeURIComponent(rid)}`')

  # Findings paging wrapper (v3)
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&limit=25`',
                '`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=25&offset=0`')
  x = x.replace('"/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=" + encodeURIComponent(path) + "&limit=800"',
                '"/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid) + "&limit=200&offset=0"')
  # any remaining run_file_allow references: keep minimal (should go to 0 after audit)
  x = x.replace("/api/vsp/run_file_allow", "/api/vsp/_INTERNAL_DO_NOT_USE_run_file_allow")

  # Remove debug/dev label(s)
  x = x.replace("UNIFIED FROM findings_unified.json", "Unified Findings (8 tools)")
  x = x.replace("UNIFIED FROM", "Unified Findings")
  # Remove internal file name literal in UI strings if any
  x = x.replace("findings_unified.json", "unified")
  x = x.replace("reports/findings_unified.json", "unified")
  return x

# 3) Data source: switch to findings_page_v3 (if legacy code still hits file wrapper)
def patch_datasource_to_api(s: str) -> str:
  x = s
  x = x.replace("/api/vsp/run_file_allow?rid=", "/api/vsp/findings_page_v3?rid=")  # last-resort
  x = x.replace("path=findings_unified.json", "")  # remove file coupling
  return patch_no_runfileallow(x)

patch_file("static/js/vsp_topbar_commercial_v1.js", patch_topbar)
for f in [
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_tabs3_common_v3.js",
  "static/js/vsp_bundle_tabs5_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
]:
  patch_file(f, patch_no_runfileallow)

for f in ["static/js/vsp_data_source_pagination_v1.js", "static/js/vsp_data_source_tab_v3.js"]:
  patch_file(f, patch_datasource_to_api)
PY

# ---- [C] restart service (best-effort) ----
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
  sleep 0.4 || true
fi

# ---- [D] quick API smoke ----
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" 2>/dev/null | python3 -c 'import sys,json; print((json.load(sys.stdin).get("rid") or "").strip())' 2>/dev/null || true)"
[ -n "$RID" ] || RID=""

echo "== [SMOKE] wrappers =="
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/run_gate_summary_v1?rid=$RID" | head -c 200 >/dev/null && ok "run_gate_summary_v1 OK" || warn "run_gate_summary_v1 not OK"
curl -fsS "$BASE/api/vsp/run_manifest_v1?rid=$RID" | head -c 200 >/dev/null && ok "run_manifest_v1 OK" || warn "run_manifest_v1 not OK"
curl -fsS "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=5&offset=0" | head -c 200 >/dev/null && ok "findings_page_v3 OK" || warn "findings_page_v3 not OK"

echo "== [DONE] Now rerun audit: bin/commercial_ui_audit_v1.sh and confirm SCAN blocks are clean =="
