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
