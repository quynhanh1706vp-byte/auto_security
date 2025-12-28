#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "[VSP_CONTRACT_V1] ROOT=$ROOT"

HELPER="$ROOT/vsp_status_contract_v1.py"
if [ -f "$HELPER" ]; then
  cp "$HELPER" "$HELPER.bak_$(date +%Y%m%d_%H%M%S)"
fi

cat > "$HELPER" << 'PY'
# vsp_status_contract_v1.py
# Commercial contract: stable run_status JSON + last-marker stage parsing + timeout fields
from __future__ import annotations
import os, re, time
from typing import Any, Dict, Optional, Tuple

STAGE_MARKER_RX = re.compile(r"=+\s*\[(\d+)\s*/\s*(\d+)\]\s*([^\r\n=]+?)\s*=+", re.IGNORECASE)

def _env_int(name: str, default: int) -> int:
    try:
        v = os.getenv(name, "")
        if v.strip() == "":
            return int(default)
        return int(float(v))
    except Exception:
        return int(default)

def env_timeouts_v1() -> Tuple[int, int]:
    stall = _env_int("VSP_UIREQ_STALL_TIMEOUT_SEC", _env_int("VSP_STALL_TIMEOUT_SEC", 600))
    total = _env_int("VSP_UIREQ_TOTAL_TIMEOUT_SEC", _env_int("VSP_TOTAL_TIMEOUT_SEC", 7200))
    if stall < 1: stall = 1
    if total < 1: total = 1
    return stall, total

def clamp_int(v: Any, lo: int, hi: int, default: int) -> int:
    try:
        x = int(float(v))
        if x < lo: return lo
        if x > hi: return hi
        return x
    except Exception:
        return default

def last_stage_marker_from_text(text: str) -> Optional[Dict[str, Any]]:
    last = None
    for m in STAGE_MARKER_RX.finditer(text or ""):
        idx = int(m.group(1))
        total = int(m.group(2))
        name = (m.group(3) or "").strip()
        last = {"stage_index": max(0, idx - 1), "stage_total": max(total, 1), "stage_name": name, "stage_raw": m.group(0)}
    return last

def read_tail(path: str, max_bytes: int = 200_000) -> str:
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            start = max(0, size - max_bytes)
            f.seek(start, 0)
            b = f.read()
        return b.decode("utf-8", errors="ignore")
    except Exception:
        return ""

def derive_stage_from_log(status: Dict[str, Any]) -> Dict[str, Any]:
    log_path = status.get("log_path") or status.get("log_file") or ""
    if not isinstance(log_path, str) or log_path.strip() == "":
        return status
    txt = read_tail(log_path)
    m = last_stage_marker_from_text(txt)
    if not m:
        return status
    status.setdefault("stage_total", m["stage_total"])
    status["stage_index"] = m["stage_index"]
    status["stage_name"] = m["stage_name"]
    status["stage_marker"] = m["stage_raw"]
    return status

def normalize_run_status_payload(payload: Any) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        payload = {"ok": False, "status": "ERROR", "final": True, "error": "INVALID_STATUS_PAYLOAD"}

    stall, total = env_timeouts_v1()

    payload.setdefault("ok", bool(payload.get("ok", False)))
    payload.setdefault("status", payload.get("status") or "UNKNOWN")
    payload.setdefault("final", bool(payload.get("final", False)))
    payload.setdefault("error", payload.get("error") or "")
    payload.setdefault("req_id", payload.get("req_id") or "")

    payload["stall_timeout_sec"] = int(payload.get("stall_timeout_sec") or stall)
    payload["total_timeout_sec"] = int(payload.get("total_timeout_sec") or total)

    payload.setdefault("killed", bool(payload.get("killed", False)))
    payload.setdefault("kill_reason", payload.get("kill_reason") or "")

    payload.setdefault("stage_index", clamp_int(payload.get("stage_index", 0), 0, 9999, 0))
    payload.setdefault("stage_total", clamp_int(payload.get("stage_total", 0), 0, 9999, 0))
    payload.setdefault("stage_name", payload.get("stage_name") or payload.get("stage") or "")
    payload["progress_pct"] = clamp_int(payload.get("progress_pct", 0), 0, 100, 0)

    payload = derive_stage_from_log(payload)

    sig = payload.get("stage_sig") or ""
    if not isinstance(sig, str) or sig.strip() == "":
        sig = f"{payload.get('stage_index','')}/{payload.get('stage_total','')}|{payload.get('stage_name','')}|{payload.get('progress_pct','')}"
    payload["stage_sig"] = sig

    payload.setdefault("updated_at", int(time.time()))
    return payload
PY

echo "[VSP_CONTRACT_V1] wrote helper: $HELPER"

# Patch run_status_v1 jsonify wrapper
python3 - "$ROOT" << 'PY'
import re, sys, time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
candidates = []
for p in root.rglob("*.py"):
    try:
        t = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if "run_status_v1" in t and "jsonify(" in t:
        candidates.append(p)

if not candidates:
    print("[VSP_CONTRACT_V1][WARN] No python file contains run_status_v1 + jsonify().")
    sys.exit(0)

def patch_one(p: Path) -> bool:
    txt = p.read_text(encoding="utf-8", errors="ignore")
    if "VSP_CONTRACT_V1_PATCH" in txt:
        print(f"[SKIP] already patched: {p}")
        return False

    lines = txt.splitlines(True)
    changed = False

    # ensure import
    if "import vsp_status_contract_v1 as vsp_sc" not in txt:
        import_line = "import vsp_status_contract_v1 as vsp_sc  # VSP_CONTRACT_V1_PATCH\n"
        ins = 0
        for i, ln in enumerate(lines[:250]):
            if ln.startswith("import ") or ln.startswith("from "):
                ins = i + 1
        lines.insert(ins, import_line)
        changed = True

    txt2 = "".join(lines)

    # patch inside def run_status_v1 block first; fallback to nearby replacement
    def_rx = re.compile(r"^def\s+run_status_v1\s*\(.*\)\s*:\s*$", re.M)
    m = def_rx.search(txt2)
    def replace_return(line: str) -> str:
        return re.sub(
            r"(\s*)return\s+jsonify\((.*)\)(\s*(?:,\s*[^#\n]+)?)\s*$",
            r"\1return jsonify(vsp_sc.normalize_run_status_payload(\2))\3\n",
            line
        )

    if m:
        start = m.start()
        after = txt2[m.end():]
        next_m = re.search(r"^def\s+\w+\s*\(.*\)\s*:\s*$", after, flags=re.M)
        end = m.end() + (next_m.start() if next_m else len(after))
        block = txt2[start:end]
        rest = txt2[end:]
        blk = block.splitlines(True)
        for i, ln in enumerate(blk):
            if "return jsonify(" in ln:
                ln2 = replace_return(ln)
                if ln2 != ln:
                    blk[i] = ln2
                    changed = True
                    break
        txt3 = "".join(blk) + rest
    else:
        L = txt2.splitlines(True)
        out = []
        for i, ln in enumerate(L):
            if "return jsonify(" in ln:
                win = "".join(L[max(0, i-60):min(len(L), i+60)])
                if "run_status_v1" in win:
                    ln2 = replace_return(ln)
                    if ln2 != ln:
                        ln = ln2
                        changed = True
            out.append(ln)
        txt3 = "".join(out)

    if not changed:
        print(f"[VSP_CONTRACT_V1][WARN] No change applied: {p}")
        return False

    bak = p.with_suffix(p.suffix + f".bak_contract_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(txt, encoding="utf-8")
    p.write_text(txt3, encoding="utf-8")
    print(f"[OK] patched: {p} (backup: {bak.name})")
    return True

n = 0
for p in candidates:
    if patch_one(p):
        n += 1
print(f"[VSP_CONTRACT_V1] done. patched_files={n} candidates={len(candidates)}")
PY

# Patch tail parser search->lastmatch (best-effort)
python3 - "$ROOT" << 'PY'
import re, time, sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
rx_stage_hint = re.compile(r"(STAGE|MARKER|PROGRESS|/\d+\])", re.I)

def should_patch(txt: str) -> bool:
    if "VSP_TAIL_LASTMATCH_V1" in txt:
        return False
    if "run_status" in txt and "re.search" in txt and ("=====" in txt or "/8]" in txt):
        return True
    if "tail" in txt.lower() and "parser" in txt.lower():
        return True
    return False

def patch_file(p: Path) -> bool:
    txt = p.read_text(encoding="utf-8", errors="ignore")
    if not should_patch(txt):
        return False
    if "re.search(" not in txt:
        return False

    lines = txt.splitlines(True)
    helper = "\n# VSP_TAIL_LASTMATCH_V1\n" \
             "def _vsp_re_search_last(rx, text):\n" \
             "    m = None\n" \
             "    for mm in rx.finditer(text or \"\"):\n" \
             "        m = mm\n" \
             "    return m\n\n"

    ins = 0
    for i, ln in enumerate(lines[:300]):
        if ln.startswith("import ") or ln.startswith("from "):
            ins = i + 1
    lines.insert(ins, helper)

    out = []
    changed = False
    for ln in lines:
        if "re.search(" in ln and rx_stage_hint.search(ln):
            ln2 = ln.replace("re.search(", "_vsp_re_search_last(")
            if ln2 != ln:
                ln = ln2
                changed = True
        out.append(ln)

    if not changed:
        return False

    bak = p.with_suffix(p.suffix + f".bak_lastmatch_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(txt, encoding="utf-8")
    p.write_text("".join(out), encoding="utf-8")
    print(f"[OK] tail-lastmatch patched: {p} (backup: {bak.name})")
    return True

patched = 0
for p in root.rglob("*.py"):
    try:
        if patch_file(p):
            patched += 1
    except Exception:
        pass

print(f"[VSP_CONTRACT_V1] tail_parser_patch_done patched_files={patched}")
PY

echo "[VSP_CONTRACT_V1] All done."
echo "NEXT (manual): restart UI gateway and re-run smoke."
