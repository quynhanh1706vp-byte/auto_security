#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need curl; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

W="wsgi_vsp_ui_gateway.py"
JS_OVER="static/js/vsp_runs_reports_overlay_v1.js"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

if [ -f "$JS_OVER" ]; then
  cp -f "$JS_OVER" "${JS_OVER}.bak_stop_v3_${TS}"
  echo "[BACKUP] ${JS_OVER}.bak_stop_v3_${TS}"
else
  echo "[WARN] missing $JS_OVER (skip overlay patch)"
fi

cp -f "$W" "${W}.bak_stop_v3_${TS}"
echo "[BACKUP] ${W}.bak_stop_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, textwrap

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

def find_handler_name(route: str):
    # returns function name handling that route, if present
    pat = rf'@app\.route\(\s*(["\']){re.escape(route)}\1[^)]*\)\s*\n(?:@app\.route\([^\n]*\)\s*\n)*def\s+([A-Za-z0-9_]+)\s*\('
    m = re.search(pat, s, flags=re.M)
    return m.group(2) if m else None

v1_name = find_handler_name("/api/ui/runs_kpi_v1")
v2_name = find_handler_name("/api/ui/runs_kpi_v2")
v3_name = find_handler_name("/api/ui/runs_kpi_v3")

# We'll make v3 proxy to v2 (or v1 fallback) to avoid 500.
proxy_marker = "VSP_P2_RUNS_KPI_V3_PROXY_V1"

def make_proxy_body(v2n, v1n):
    v2call = f"{v2n}()" if v2n else "None"
    v1call = f"{v1n}()" if v1n else "None"
    body = f"""
    # ===================== {proxy_marker} =====================
    # NOTE: keep KPI endpoint stable; proxy v3 -> v2 to prevent 500 from older JS.
    try:
        if {repr(bool(v2n))}:
            return {v2call}
    except Exception as e:
        try:
            if {repr(bool(v1n))}:
                return {v1call}
        except Exception:
            pass
        return jsonify(ok=False, err=str(e), ts=int(time.time())), 200
    # If no v2/v1 handler found, degrade gracefully
    return jsonify(ok=False, err="runs_kpi_v2 handler not found", ts=int(time.time())), 200
    # ===================== /{proxy_marker} =====================
"""
    return textwrap.dedent(body).lstrip("\n")

def replace_route_func(route: str, new_body: str):
    # Replace existing function body for given route (best-effort)
    # Capture: decorators+def header (group1), body (group4), stop at next top-level @ or def
    pat = rf'(?s)(@app\.route\(\s*(["\']){re.escape(route)}\2[^)]*\)\s*\n(?:@app\.route\([^\n]*\)\s*\n)*def\s+[A-Za-z0-9_]+\s*\([^)]*\)\s*:\s*\n)(.*?)(?=\n@|\ndef\s|\Z)'
    m = re.search(pat, s)
    if not m:
        return None, 0
    head = m.group(1)
    return head + new_body, 1

changed = 0

if v3_name and proxy_marker not in s:
    new_body = make_proxy_body(v2_name, v1_name)
    repl, n = replace_route_func("/api/ui/runs_kpi_v3", new_body)
    if n:
        s = re.sub(r'(?s)(@app\.route\(\s*(["\'])/api/ui/runs_kpi_v3\2[^)]*\)\s*\n(?:@app\.route\([^\n]*\)\s*\n)*def\s+[A-Za-z0-9_]+\s*\([^)]*\)\s*:\s*\n)(.*?)(?=\n@|\ndef\s|\Z)',
                   lambda mm: mm.group(1) + new_body, s, count=1)
        changed += 1

# If route not present, append a small proxy endpoint (safe, returns 200 ok/false on errors).
if not v3_name:
    block = f"""
# ===================== {proxy_marker}_APPEND =====================
@app.route("/api/ui/runs_kpi_v3")
def runs_kpi_v3():
{make_proxy_body(v2_name, v1_name)}
# ===================== /{proxy_marker}_APPEND =====================
"""
    s += "\n" + textwrap.dedent(block)
    changed += 1

w.write_text(s, encoding="utf-8")
print(f"[OK] wsgi patched: v3->v2 proxy applied. changes={changed} v1={v1_name} v2={v2_name} v3={v3_name}")
PY

if [ -f "$JS_OVER" ]; then
  python3 - <<'PY'
from pathlib import Path
import re, time, textwrap

p = Path("static/js/vsp_runs_reports_overlay_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_DISABLE_OVERLAY_KPI_V1"

if marker not in s:
    # Disable ONLY the old overlay KPI loader to avoid v3/canvas/DOM-null issues.
    # Keep everything else in overlay working.
    # Try to inject at start of loadRunsKpi function.
    # Handles: function loadRunsKpi(...) { ... } or async function loadRunsKpi(...) { ... }
    pat = r'(?m)^(async\s+)?function\s+loadRunsKpi\s*\([^)]*\)\s*\{\s*$'
    m = re.search(pat, s)
    if m:
        inject = textwrap.dedent(f"""
          // ===================== {marker} =====================
          // Compact KPI script handles KPI; disable overlay KPI to prevent v3/500 and heavy canvas/layout.
          try {{
            if (window.__vsp_runs_kpi_compact_v3) return;
            if (window.__VSP_DISABLE_OVERLAY_KPI === true) return;
          }} catch(e) {{}}
          // ===================== /{marker} =====================
        """).rstrip() + "\n"
        # Insert right after the function opening line
        s = re.sub(pat, lambda mm: mm.group(0) + "\n" + inject, s, count=1)
    else:
        # Fallback: global flag + guard where we can
        s = "window.__VSP_DISABLE_OVERLAY_KPI=true;\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] overlay KPI disabled (best-effort).")
PY

  node --check "$JS_OVER" >/dev/null && echo "[OK] node --check overlay OK"
fi

python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "[INFO] restarting service..."
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.6

echo "== sanity: KPI v2 should be 200 =="
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 260; echo

echo "== sanity: KPI v3 should NOT 500 anymore (proxy -> v2) =="
curl -sS "$BASE/api/ui/runs_kpi_v3?days=30" | head -c 260; echo

echo "[DONE] p2_fix_runs_kpi_stop_v3_overlay_v1"
