#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
JS="static/js/vsp_c_runs_v1.js"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4850_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$APP" "$OUT/${APP}.bak_before_${TS}"
cp -f "$JS"  "$OUT/$(basename "$JS").bak_before_${TS}"
echo "[OK] backup => $OUT" | tee -a "$OUT/log.txt"

export APP JS OUT

python3 - <<'PY' | tee -a "$OUT/log.txt"
import os, re, pathlib

app_path = pathlib.Path(os.environ["APP"])
js_path  = pathlib.Path(os.environ["JS"])
out_dir  = pathlib.Path(os.environ["OUT"])
marker = "VSP_P4850_RUNS3_ITEMS_ALIAS_MW_V1"

# ---------------- Backend patch (vsp_demo_app.py) ----------------
s = app_path.read_text(encoding="utf-8", errors="replace")
if marker in s:
    print("[OK] backend already patched")
else:
    # find "<appvar> = Flask(" at top-level or any indent
    m = re.search(r'(?m)^(?P<indent>[ \t]*)(?P<var>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*Flask\s*\(', s)
    if not m:
        raise SystemExit("[ERR] cannot find app = Flask(...) in vsp_demo_app.py")
    indent = m.group("indent")
    appvar = m.group("var")

    # find end of Flask(...) call by paren depth scan
    call_pos = s.find("Flask", m.start())
    paren_pos = s.find("(", call_pos)
    if paren_pos < 0:
        raise SystemExit("[ERR] cannot locate '(' after Flask")
    depth = 0
    end_pos = None
    for i in range(paren_pos, len(s)):
        c = s[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                end_pos = i + 1
                break
    if end_pos is None:
        raise SystemExit("[ERR] cannot find end of Flask(...) call")

    # insert after the line ending that contains the Flask(...) expression
    nl = s.find("\n", end_pos)
    insert_at = (nl + 1) if nl != -1 else end_pos

    block = f"""{indent}# {marker}
{indent}def _vsp_p4850_runs3_contract_payload(obj):
{indent}    try:
{indent}        if isinstance(obj, dict) and ("items" not in obj) and isinstance(obj.get("runs"), list):
{indent}            obj["items"] = obj.get("runs") or []
{indent}        return obj
{indent}    except Exception:
{indent}        return obj
{indent}
{indent}@{appvar}.after_request
{indent}def _vsp_p4850_runs3_items_alias_after_request(resp):
{indent}    # Always mark when this hook is hit for runs_v3
{indent}    try:
{indent}        from flask import request
{indent}        if getattr(request, "path", "") != "/api/vsp/runs_v3":
{indent}            return resp
{indent}        # marker header for audit
{indent}        resp.headers["X-VSP-P4850-RUNS3"] = "1"
{indent}        ct = (resp.headers.get("Content-Type", "") or "").lower()
{indent}        if "application/json" not in ct:
{indent}            return resp
{indent}        raw = resp.get_data(as_text=True) or ""
{indent}        if not raw.strip():
{indent}            return resp
{indent}        import json
{indent}        obj = json.loads(raw)
{indent}        if isinstance(obj, dict) and ("items" not in obj) and isinstance(obj.get("runs"), list):
{indent}            obj = _vsp_p4850_runs3_contract_payload(obj)
{indent}            new_raw = json.dumps(obj, ensure_ascii=False)
{indent}            resp.set_data(new_raw)
{indent}            resp.headers["Content-Length"] = str(len(resp.get_data() or b""))
{indent}            resp.headers["X-VSP-P4850-RUNS3"] = "2"  # items injected
{indent}        return resp
{indent}    except Exception:
{indent}        try:
{indent}            resp.headers["X-VSP-P4850-RUNS3"] = "ERR"
{indent}        except Exception:
{indent}            pass
{indent}        return resp
"""

    s2 = s[:insert_at] + block + s[insert_at:]
    app_path.write_text(s2, encoding="utf-8")
    print(f"[OK] backend patched appvar={appvar} insert_at={insert_at}")

# ---------------- Frontend patch (vsp_c_runs_v1.js) ----------------
j = js_path.read_text(encoding="utf-8", errors="replace")
js_marker = "VSP_P4850_RUNS3_ITEMS_ALIAS_JS_V1"
if js_marker in j:
    print("[OK] frontend already patched")
else:
    # Try to patch common patterns: "const x = await y.json();" or "let x = await y.json();"
    m2 = re.search(r'(?m)^(?P<indent>[ \t]*)(const|let)\s+(?P<var>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*await\s+[A-Za-z_][A-Za-z0-9_]*\s*\.json\(\)\s*;\s*$', j)
    if not m2:
        # fallback: any "await something.json()" in a statement
        m2 = re.search(r'(?m)^(?P<indent>[ \t]*)(const|let)\s+(?P<var>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*await\s+.*?\.json\(\)\s*;\s*$', j)
    if not m2:
        print("[WARN] cannot find await *.json() assignment in runs js; skip JS patch (backend contract should still fix)")
    else:
        ind = m2.group("indent")
        v = m2.group("var")
        insert_line = m2.end()
        inject = f"\n{ind}// {js_marker}\n{ind}{v}.items = ({v}.items || {v}.runs || []);\n"
        j2 = j[:insert_line] + inject + j[insert_line:]
        js_path.write_text(j2, encoding="utf-8")
        print(f"[OK] frontend patched var={v}")

print("[OK] done")
PY

python3 -m py_compile "$APP" | tee -a "$OUT/log.txt"
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt"
else
  systemctl restart "$SVC"
  systemctl is-active "$SVC" | tee -a "$OUT/log.txt"
fi

echo "== [VERIFY] /api/vsp/runs_v3 has items ==" | tee -a "$OUT/log.txt"
HDR="$OUT/hdr.txt"
BODY="$OUT/body.json"
curl -sS -D "$HDR" -o "$BODY" "$BASE/api/vsp/runs_v3?limit=5&include_ci=1"
grep -i "X-VSP-P4850-RUNS3" -n "$HDR" || true
python3 - <<'PY' | tee -a "$OUT/log.txt"
import json, pathlib
p = pathlib.Path(r"""'"$BODY"'""")
j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "items_len=", (len(j["items"]) if isinstance(j.get("items"), list) else "NA"))
print("runs_type=", type(j.get("runs")).__name__, "runs_len=", (len(j["runs"]) if isinstance(j.get("runs"), list) else "NA"))
print("total=", j.get("total"))
PY

echo "[OK] P4850 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
