#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
JS="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p483z_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

log(){ echo "$*" | tee -a "$OUT/log.txt"; }

[ -f "$APP" ] || { log "[ERR] missing $APP"; exit 2; }
[ -f "$JS" ]  || { log "[ERR] missing $JS";  exit 2; }

cp -f "$APP" "$APP.bak_p483z_${TS}"
cp -f "$JS"  "$JS.bak_p483z_${TS}"
log "[OK] backup => $APP.bak_p483z_${TS}"
log "[OK] backup => $JS.bak_p483z_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")
marker = "P483Z_RUNS_V3_ITEMS_ALIAS"

def ensure_helper(src: str) -> str:
    if marker in src:
        return src
    # chèn helper sau khi app = Flask(...)
    m = re.search(r"^app\s*=\s*Flask\([^\n]*\)\s*$", src, flags=re.M)
    if not m:
        # fallback: chèn sau imports đầu file
        m2 = re.search(r"^(from\s+\S+|import\s+\S+)[\s\S]*?\n\n", src)
        ins_at = m2.end() if m2 else 0
        helper = (
            "\n\ndef _vsp_runs_v3_contract(resp):\n"
            f"    \"\"\"{marker}: commercial contract: always expose both 'runs' and 'items'.\"\"\"\n"
            "    try:\n"
            "        if isinstance(resp, dict):\n"
            "            if 'runs' in resp and 'items' not in resp:\n"
            "                resp['items'] = resp.get('runs')\n"
            "            if 'items' in resp and 'runs' not in resp:\n"
            "                resp['runs'] = resp.get('items')\n"
            "    except Exception:\n"
            "        pass\n"
            "    return resp\n\n"
        )
        return src[:ins_at] + helper + src[ins_at:]
    ins_at = m.end()
    helper = (
        "\n\ndef _vsp_runs_v3_contract(resp):\n"
        f"    \"\"\"{marker}: commercial contract: always expose both 'runs' and 'items'.\"\"\"\n"
        "    try:\n"
        "        if isinstance(resp, dict):\n"
        "            if 'runs' in resp and 'items' not in resp:\n"
        "                resp['items'] = resp.get('runs')\n"
        "            if 'items' in resp and 'runs' not in resp:\n"
        "                resp['runs'] = resp.get('items')\n"
        "    except Exception:\n"
        "        pass\n"
        "    return resp\n\n"
    )
    return src[:ins_at] + helper + src[ins_at:]

def wrap_jsonify_in_runs_v3(src: str) -> str:
    # tìm block handler của /api/vsp/runs_v3 và wrap return jsonify(...)
    # hỗ trợ @app.get hoặc @app.route
    pat = r"@app\.(get|route)\(\s*['\"]/api/vsp/runs_v3['\"][^\n]*\)\s*\n(def\s+\w+\([^\)]*\)\s*:\s*\n)"
    m = re.search(pat, src, flags=re.M)
    if not m:
        return src
    start = m.start()
    # tìm tới decorator tiếp theo hoặc EOF
    rest = src[m.end():]
    m2 = re.search(r"^\s*@app\.", rest, flags=re.M)
    end = m.end() + (m2.start() if m2 else len(rest))
    block = src[m.end():end]

    if "_vsp_runs_v3_contract(" in block:
        return src  # already wrapped

    # wrap các "return jsonify(...)" trong block (thường chỉ 1 return)
    def repl_return(match):
        inner = match.group(1)
        return f"return jsonify(_vsp_runs_v3_contract({inner}))"
    block2, n = re.subn(r"return\s+jsonify\(\s*([^\)]+?)\s*\)\s*$", repl_return, block, flags=re.M)
    if n == 0:
        # fallback: nếu return jsonify(dict literal multi-line) -> thêm normalize trước return cuối
        # chèn đoạn normalize trước mọi "return jsonify(" (không phá cú pháp)
        block2 = re.sub(r"return\s+jsonify\(", "return jsonify(_vsp_runs_v3_contract(", block, count=1)
        # đóng thêm 1 dấu ) trước dấu ) của jsonify ở cùng statement nếu 1-line
        # nếu multi-line thì vẫn OK vì đóng ở line cuối thường là '))' -> ta sẽ fix thêm bằng replace cuối cùng
        # best effort:
        block2 = block2.replace(")\n", "))\n", 1)
    return src[:m.end()] + block2 + src[end:]

s2 = ensure_helper(s)
s3 = wrap_jsonify_in_runs_v3(s2)

if s3 != s:
    app.write_text(s3, encoding="utf-8")
    print("[OK] patched vsp_demo_app.py (helper + runs_v3 jsonify wrapper)")
else:
    print("[WARN] no changes in vsp_demo_app.py (handler not found or already patched)")
PY

python3 - <<'PY'
from pathlib import Path
import re

js = Path("static/js/vsp_c_runs_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")
marker = "P483Z_RUNS_JS_ITEMS_OR_RUNS"

if marker in s:
    print("[OK] JS already patched")
else:
    # best-effort: thay thế các chỗ đọc data.items thành fallback items||runs
    # 1) đảm bảo có hàm normalize nhỏ gọn
    inject = (
        "\n// " + marker + "\n"
        "function vspRunsPickItems(data){\n"
        "  try{\n"
        "    if(!data) return [];\n"
        "    const it = (Array.isArray(data.items) ? data.items : null) || (Array.isArray(data.runs) ? data.runs : null);\n"
        "    return it || [];\n"
        "  }catch(e){ return []; }\n"
        "}\n\n"
    )
    # chèn gần đầu file sau 'use strict' nếu có
    m = re.search(r"(['\"]use strict['\"];?\s*\n)", s)
    if m:
        s = s[:m.end()] + inject + s[m.end():]
    else:
        s = inject + s

    # thay các pattern "const items = data.items" hoặc "let items = data.items"
    s, n1 = re.subn(r"\b(const|let)\s+items\s*=\s*data\.items\s*\|\|\s*\[\]\s*;", r"\1 items = vspRunsPickItems(data);", s)
    s, n2 = re.subn(r"\b(const|let)\s+items\s*=\s*data\.items\s*;\s*", r"\1 items = vspRunsPickItems(data);\n", s)

    # nếu code dùng data.items trực tiếp trong render, thay vài chỗ phổ biến
    s = s.replace("data.items || []", "vspRunsPickItems(data)")
    js.write_text(s, encoding="utf-8")
    print(f"[OK] patched JS: n1={n1} n2={n2}")
PY

python3 -m py_compile vsp_demo_app.py | tee -a "$OUT/log.txt"

if [ "$HAS_NODE" = "1" ]; then
  node --check "$JS" | tee -a "$OUT/log.txt"
fi

log "[INFO] restart $SVC"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

log "[OK] P483z done."
log "[NEXT] Reopen /c/runs then Ctrl+Shift+R"
log "[LOG] $OUT/log.txt"
