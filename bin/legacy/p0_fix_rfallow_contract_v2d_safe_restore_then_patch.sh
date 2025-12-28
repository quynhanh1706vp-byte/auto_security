#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_broken_snapshot_${TS}"
echo "[SNAPSHOT] ${APP}.bak_broken_snapshot_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, tokenize, io

app_py = Path("vsp_demo_app.py")

def compiles(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

# 1) If current file broken -> restore latest compiling backup
if not compiles(app_py):
    baks = sorted(app_py.parent.glob(app_py.name + ".bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)
    good = None
    for b in baks:
        if compiles(b):
            good = b
            break
    if not good:
        raise SystemExit("[ERR] current vsp_demo_app.py is broken and no compiling backup found")
    app_py.write_bytes(good.read_bytes())
    print(f"[RESTORE] vsp_demo_app.py <= {good.name}")
else:
    print("[OK] current vsp_demo_app.py compiles (will still clean old injected blocks)")

s = app_py.read_text(encoding="utf-8", errors="replace")

# 2) Remove older injected blocks + stray old function if exists
def drop_block(txt: str, open_mark: str, close_mark: str) -> str:
    if open_mark in txt and close_mark in txt:
        pre, mid = txt.split(open_mark, 1)
        _, post = mid.split(close_mark, 1)
        return pre.rstrip() + "\n\n" + post.lstrip()
    return txt

s = drop_block(s,
    "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1 =====================",
    "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1 =====================",
)
s = drop_block(s,
    "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================",
    "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================",
)

# remove any previous stray decorator/function by our name (top-level)
s = re.sub(
    r'(?ms)^\s*@app\.after_request\s*\n^\s*def\s+_vsp_p2_rfallow_contract_after_request\s*\(resp\)\s*:\s*\n.*?(?=^\S|\Z)',
    '',
    s
)

# ensure import json
if re.search(r'^\s*import\s+json\b', s, re.M) is None:
    m = re.search(r'^(?:from\s+\S+\s+import\s+.*|import\s+\S+)(?:\s*\n(?:from\s+\S+\s+import\s+.*|import\s+\S+))*', s, re.M)
    if m:
        s = s[:m.end()] + "\nimport json\n" + s[m.end():]
    else:
        s = "import json\n" + s

# 3) Find safe insertion point: right AFTER the 'app = Flask(...)' statement at paren_level==0
# Use tokenize to avoid inserting inside open parens / strings.
lines = s.splitlines(True)
src = s

# locate start line index for top-level "app = Flask("
app_line_idx = None
for i, line in enumerate(lines):
    if re.match(r'^app\s*=\s*Flask\(', line):
        app_line_idx = i
        break
if app_line_idx is None:
    raise SystemExit("[ERR] cannot find top-level: app = Flask(")

# now tokenize to find the NEWLINE that ends that statement while paren_level==0
tokgen = tokenize.generate_tokens(io.StringIO(src).readline)
paren = 0
end_line = None
seen_app_stmt = False

for tok in tokgen:
    ttype, tstr, (sl, sc), (el, ec), _ = tok
    if tstr in ("(", "[", "{"):
        paren += 1
    elif tstr in (")", "]", "}"):
        paren = max(0, paren - 1)

    if sl == app_line_idx + 1 and sc == 0 and ttype == tokenize.NAME and tstr == "app":
        seen_app_stmt = True

    if seen_app_stmt and ttype in (tokenize.NEWLINE,) and paren == 0:
        end_line = el  # 1-based line number
        break

if end_line is None:
    # fallback: insert after that single line
    end_line = app_line_idx + 1

insert_pos = sum(len(lines[i]) for i in range(end_line))  # insert AFTER end_line

MARK_OPEN = "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2D_SAFE ====================="
MARK_CLOSE = "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2D_SAFE ====================="

if MARK_OPEN in s and MARK_CLOSE in s:
    print("[OK] V2D marker already exists (skip inject)")
else:
    block = "\n".join([
        MARK_OPEN,
        "def _vsp_p2_rfallow_contract_after_request(resp):",
        "    # Enrich wrapper contract for /api/vsp/run_file_allow ONLY.",
        "    # IMPORTANT: do NOT wrap/modify raw JSON files (run_gate_summary.json, findings_unified.json, ...).",
        "    try:",
        "        from flask import request",
        "        if request.path != '/api/vsp/run_file_allow':",
        "            return resp",
        "        txt = resp.get_data(as_text=True) if hasattr(resp, 'get_data') else ''",
        "        if not txt:",
        "            return resp",
        "        ctype = (resp.headers.get('Content-Type') or '').lower()",
        "        if ('application/json' not in ctype) and (not txt.lstrip().startswith('{')):",
        "            return resp",
        "        try:",
        "            d = json.loads(txt)",
        "        except Exception:",
        "            return resp",
        "        if not isinstance(d, dict):",
        "            return resp",
        "        # wrapper detection: only touch payloads that already look like wrapper",
        "        if not ('path' in d or 'marker' in d or 'err' in d or 'ok' in d):",
        "            return resp",
        "        # If this looks like a raw file JSON (typical keys), skip",
        "        raw_keys = {'by_tool','counts_total','findings','meta','runs','items'}",
        "        if any(k in d for k in raw_keys) and ('err' not in d and 'marker' not in d):",
        "            return resp",
        "        rid = (request.args.get('rid','') or d.get('rid','') or '')",
        "        path_raw = request.args.get('path','')",
        "        if not path_raw:",
        "            path_raw = (d.get('path','') or '')",
        "        ok = bool(d.get('ok'))",
        "        err = (d.get('err') or '')",
        "        el = err.lower()",
        "        http = d.get('http', None)",
        "        if http is None:",
        "            if ok: http = 200",
        "            elif ('not allowed' in el) or ('forbidden' in el) or ('deny' in el): http = 403",
        "            elif ('not found' in el) or ('missing' in el) or ('no such' in el): http = 404",
        "            else: http = 400",
        "        allow = d.get('allow', None)",
        "        if allow is None or not isinstance(allow, list):",
        "            allow = []",
        "        d['ok'] = ok",
        "        d['http'] = int(http)",
        "        d['allow'] = allow",
        "        d['rid'] = rid",
        "        d['path'] = path_raw",
        "        if 'marker' not in d:",
        "            d['marker'] = 'VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2D_SAFE'",
        "        resp.set_data(json.dumps(d, ensure_ascii=False))",
        "        resp.headers['Content-Type'] = 'application/json; charset=utf-8'",
        "        return resp",
        "    except Exception:",
        "        return resp",
        "",
        "# attach safely (NO decorator) -> avoids SyntaxError entirely",
        "try:",
        "    app.after_request(_vsp_p2_rfallow_contract_after_request)  # type: ignore[name-defined]",
        "except Exception:",
        "    pass",
        MARK_CLOSE,
        "",
    ]) + "\n"

    s = s[:insert_pos] + "\n" + block + s[insert_pos:]
    print("[OK] injected V2D SAFE block")

app_py.write_text(s, encoding="utf-8")
py_compile.compile(str(app_py), doraise=True)
print("[OK] py_compile:", app_py)
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
