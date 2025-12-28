#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_force_runapi_ast_${TS}"
echo "[BACKUP] $F.bak_force_runapi_ast_${TS}"

python3 - << 'PY'
import ast, re
from pathlib import Path

p = Path("vsp_demo_app.py")
src = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")
marker = "# === VSP_RUN_API_FORCE_REGISTER_V2_AST (do not edit) ==="
if marker in src:
    print("[INFO] marker already present; skip")
else:
    tree = ast.parse(src)
    lines = src.splitlines(True)

    # find first assignment like: <name> = Flask(...)
    target = None  # (var_name, lineno, end_lineno)
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
            fn = node.value.func
            fn_name = None
            if isinstance(fn, ast.Name):
                fn_name = fn.id
            elif isinstance(fn, ast.Attribute):
                fn_name = fn.attr
            if fn_name != "Flask":
                continue
            if not node.targets:
                continue
            t0 = node.targets[0]
            if isinstance(t0, ast.Name):
                var = t0.id
            else:
                continue
            lineno = getattr(node, "lineno", None)
            end_lineno = getattr(node, "end_lineno", lineno)
            if lineno:
                # ưu tiên biến tên app nếu có
                if var == "app":
                    target = (var, lineno, end_lineno)
                    break
                if target is None:
                    target = (var, lineno, end_lineno)

    if target is None:
        raise SystemExit("[ERR] AST cannot find '<var> = Flask(...)' in vsp_demo_app.py")

    var, lineno, end_lineno = target
    # detect indent of that line (works both top-level and inside function)
    assign_line = lines[lineno-1]
    indent = re.match(r"^(\s*)", assign_line).group(1)

    inject = f"""{indent}{marker}
{indent}def _vsp__load_runapi_bp__v2():
{indent}    try:
{indent}        # normal import (package-style)
{indent}        from run_api.vsp_run_api_v1 import bp_vsp_run_api_v1
{indent}        return bp_vsp_run_api_v1
{indent}    except Exception as e1:
{indent}        try:
{indent}            # fallback: load by file path (works even if run_api isn't a package)
{indent}            import importlib.util
{indent}            from pathlib import Path as _Path
{indent}            mod_path = _Path(__file__).resolve().parent / "run_api" / "vsp_run_api_v1.py"
{indent}            spec = importlib.util.spec_from_file_location("vsp_run_api_v1_dyn_v2", str(mod_path))
{indent}            mod = importlib.util.module_from_spec(spec)
{indent}            assert spec and spec.loader
{indent}            spec.loader.exec_module(mod)
{indent}            return getattr(mod, "bp_vsp_run_api_v1", None)
{indent}        except Exception as e2:
{indent}            print("[VSP_RUN_API] WARN load failed:", repr(e1), repr(e2))
{indent}            return None
{indent}
{indent}try:
{indent}    _bp = _vsp__load_runapi_bp__v2()
{indent}    if _bp is not None:
{indent}        _bps = getattr({var}, "blueprints", None) or {{}}
{indent}        if getattr(_bp, "name", None) in _bps:
{indent}            print("[VSP_RUN_API] already registered:", _bp.name)
{indent}        else:
{indent}            {var}.register_blueprint(_bp)
{indent}            print("[VSP_RUN_API] OK registered: /api/vsp/run_v1 + /api/vsp/run_status_v1/<REQ_ID>")
{indent}    else:
{indent}        print("[VSP_RUN_API] WARN: bp_vsp_run_api_v1 is None")
{indent}except Exception as e:
{indent}    print("[VSP_RUN_API] WARN: cannot register run_api blueprint:", repr(e))
{indent}# === END VSP_RUN_API_FORCE_REGISTER_V2_AST ===
"""

    # insert right after end_lineno
    insert_at = end_lineno  # 1-based line index; insert after => list index = end_lineno
    lines2 = lines[:insert_at] + [inject] + lines[insert_at:]
    out = "".join(lines2)
    p.write_text(out, encoding="utf-8")
    print(f"[OK] injected after Flask() assign: var={var} line={lineno}..{end_lineno} indent_len={len(indent)}")

import py_compile
py_compile.compile("vsp_demo_app.py", doraise=True)
print("[OK] py_compile OK")
PY
