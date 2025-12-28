#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true

python3 - <<'PY'
from pathlib import Path
import time, re, py_compile

TS = time.strftime("%Y%m%d_%H%M%S")
MARK = "VSP_P1_RUN_FILE_ALLOW_GATE_SUMMARY_JSONIFY_V6"
ROUTE = "/api/vsp/run_file_allow"

# Prefer gateway first
targets = [Path("wsgi_vsp_ui_gateway.py"), Path("vsp_demo_app.py")]
targets = [p for p in targets if p.exists()]
if not targets:
    raise SystemExit("[ERR] missing wsgi_vsp_ui_gateway.py / vsp_demo_app.py")

def find_best_def_block(src: str):
    # Collect top-level defs with their start/end
    lines = src.splitlines(True)
    def_starts = []
    for i, ln in enumerate(lines):
        if re.match(r"^def\s+\w+\s*\(", ln):
            def_starts.append(i)
    if not def_starts:
        return None

    def block_span(i0):
        # end at next top-level def
        for j in def_starts:
            if j > i0:
                return i0, j
        return i0, len(lines)

    candidates = []
    for i0 in def_starts:
        a, b = block_span(i0)
        chunk = "".join(lines[a:b])
        name = re.match(r"^def\s+(\w+)\s*\(", lines[a]).group(1)

        score = 0
        if "run_file_allow" in name.lower(): score += 50
        if ROUTE in chunk: score += 80
        # heuristics: function touches request.args path/rid and returns send_file
        if "request.args" in chunk and "path" in chunk: score += 20
        if "send_file" in chunk or "send_from_directory" in chunk: score += 20
        if "run_file_allow" in chunk: score += 15

        if score > 0:
            candidates.append((score, name, a, b, chunk))

    candidates.sort(key=lambda x: (-x[0], x[1]))
    return candidates[0] if candidates else None, lines

def patch_file(p: Path) -> bool:
    src = p.read_text(encoding="utf-8", errors="replace")
    if MARK in src:
        print("[SKIP] marker already in", p)
        return False

    best, lines = find_best_def_block(src)
    if not best:
        print("[WARN] no suitable def block in", p)
        return False

    score, name, a, b, chunk = best
    print("[INFO] chosen handler in", p, "=>", name, "score=", score)

    # find first return send_file(...) or send_from_directory(...)
    m = re.search(r"(?m)^(?P<ind>\s*)return\s+.*?\b(send_file|send_from_directory)\s*\(\s*(?P<arg>[^,\n\)]+)", chunk)
    if not m:
        print("[WARN] no return send_file/send_from_directory in chosen block:", name)
        return False

    ind = m.group("ind")
    arg = m.group("arg").strip()

    inject = f"""{ind}# ===================== {MARK} =====================
{ind}# If requesting run_gate_summary.json/run_gate.json: serve as jsonify with ok:true (avoid send_file passthrough)
{ind}try:
{ind}    _path = (locals().get("path") or locals().get("req_path") or "")
{ind}    _rid  = (locals().get("rid") or locals().get("run_id") or "")
{ind}    if _path and (str(_path).endswith("run_gate_summary.json") or str(_path).endswith("run_gate.json")):
{ind}        import json as _json
{ind}        from pathlib import Path as _Path
{ind}        try:
{ind}            from flask import jsonify as _jsonify
{ind}        except Exception:
{ind}            import flask as _flask
{ind}            _jsonify = _flask.jsonify
{ind}        _fp = {arg}
{ind}        _j = _json.loads(_Path(str(_fp)).read_text(encoding="utf-8", errors="replace"))
{ind}        if isinstance(_j, dict):
{ind}            _j.setdefault("ok", True)
{ind}            if _rid:
{ind}                _j.setdefault("rid", _rid)
{ind}                _j.setdefault("run_id", _rid)
{ind}        return _jsonify(_j)
{ind}except Exception:
{ind}    pass
{ind}# ===================== /{MARK} =====================
"""

    # insert before that return line
    ins_at = m.start()
    chunk2 = chunk[:ins_at] + inject + chunk[ins_at:]

    # rebuild file
    new_lines = lines[:a] + [chunk2] + lines[b:]
    out = "".join(new_lines)

    bak = p.with_name(p.name + f".bak_gatejsonify_v6_{TS}")
    bak.write_text(src, encoding="utf-8")
    print("[BACKUP]", bak)

    p.write_text(out, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] patched+compiled:", p)
    return True

patched_any = False
for p in targets:
    if patch_file(p):
        patched_any = True
        break  # patch only one (the most likely gateway)

if not patched_any:
    raise SystemExit("[ERR] could not patch any target file (no suitable handler found)")
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] v6 gate-summary jsonify patch applied."
