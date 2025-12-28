#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_runsfs_jsonsort_v2_${TS}"
echo "[BACKUP] $F.bak_runsfs_jsonsort_v2_${TS}"

python3 - << 'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

# 1) Replace our previous sort block with a safer one (if present)
sort_pat = r"# === VSP_COMMERCIAL_RUNS_FS_SORT_V1 ===[\s\S]*?# === END VSP_COMMERCIAL_RUNS_FS_SORT_V1 ==="
sort_rep = r"""# === VSP_COMMERCIAL_RUNS_FS_SORT_V2 ===
    # Commercial sort: CI-first + newest-first (mtime fallback), apply limit AFTER sort.
    try:
        import os, datetime
        from pathlib import Path as _Path
        _OUT = str(_Path(__file__).resolve().parents[1] / "out")  # .../SECURITY_BUNDLE/out

        def _mtime(it):
            rid = (it.get("run_id") or "").strip()
            if not rid: return 0.0
            try:
                return os.path.getmtime(os.path.join(_OUT, rid))
            except Exception:
                return 0.0

        def _created_ts(it):
            s = (it.get("created_at") or "").strip()
            if not s: return 0.0
            try:
                s2 = s[:-1] if s.endswith("Z") else s
                dt = datetime.datetime.fromisoformat(s2)
                return dt.timestamp()
            except Exception:
                return 0.0

        def _key(it):
            rid = (it.get("run_id") or "")
            ci_first = 0 if rid.startswith("RUN_VSP_CI_") else 1
            return (ci_first, -max(_created_ts(it), _mtime(it)), rid)

        items.sort(key=_key)
        try:
            items[:] = items[:int(limit)]
        except Exception:
            pass
    except Exception:
        pass
    # === END VSP_COMMERCIAL_RUNS_FS_SORT_V2 ===
"""
if re.search(sort_pat, txt):
    txt = re.sub(sort_pat, sort_rep, txt, count=1)
    print("[OK] upgraded sort block to V2 (safer out path)")
else:
    print("[INFO] no old sort block found (will rely on json guard only)")

# 2) Force JSON guard for vsp_runs_index_v3_fs (wrap whole function)
# find def
m = re.search(r"(?m)^def\s+vsp_runs_index_v3_fs\s*\(\s*\)\s*:\s*$", txt)
if not m:
    raise SystemExit("[ERR] cannot find def vsp_runs_index_v3_fs()")

start = m.start()
# end at next top-level def or decorator
m2 = re.search(r"(?m)^(?=def\s+\w+\s*\(|@)", txt[m.end():])
end = m.end() + (m2.start() if m2 else (len(txt) - m.end()))
block = txt[start:end]

GUARD_MARK = "# === VSP_COMMERCIAL_RUNS_FS_JSON_GUARD_V2 ==="
if GUARD_MARK in block:
    print("[SKIP] JSON guard already present")
else:
    lines = block.splitlines(True)
    # locate first body line index (after def)
    def_i = 0
    # detect indentation of first body line
    body_i = 1
    while body_i < len(lines) and lines[body_i].strip() == "":
        body_i += 1

    # if function is empty, still guard
    base_indent = "    "
    # indent entire existing body by 4 spaces
    body = [base_indent + ln if ln.strip() != "" else ln for ln in lines[body_i:]]

    inject = []
    inject.append(lines[0])  # def line
    # keep possible blank lines between def and body
    inject.extend(lines[1:body_i])
    inject.append(f"{base_indent}{GUARD_MARK}\n")
    inject.append(f"{base_indent}try:\n")
    # add body under try with +4 spaces
    inject.extend([base_indent + ln if ln.strip() != "" else ln for ln in body])
    inject.append(f"{base_indent}except Exception as e:\n")
    inject.append(f"{base_indent}    try:\n")
    inject.append(f"{base_indent}        from flask import jsonify as _jsonify\n")
    inject.append(f"{base_indent}        return _jsonify({{'ok': False, 'error': repr(e), 'items': []}}), 500\n")
    inject.append(f"{base_indent}    except Exception:\n")
    inject.append(f"{base_indent}        return ('{{\"ok\":false,\"error\":\"runs_index_v3_fs_failed\"}}', 500, {{'Content-Type':'application/json'}})\n")
    inject.append(f"{base_indent}# === END VSP_COMMERCIAL_RUNS_FS_JSON_GUARD_V2 ===\n")

    new_block = "".join(inject)
    txt = txt[:start] + new_block + txt[end:]
    print("[OK] wrapped vsp_runs_index_v3_fs() with JSON guard")

p.write_text(txt, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
