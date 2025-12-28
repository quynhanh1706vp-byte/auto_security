from pathlib import Path
import json
import re

def get_vsp_root():
    return Path(__file__).resolve().parents[2]

def get_out_dir():
    return get_vsp_root() / "out"

RUN_PATTERN = re.compile(r"^RUN_VSP_FULL_EXT_(\d{8})_(\d{6})$")

def is_valid_run_name(name: str) -> bool:
    return RUN_PATTERN.match(name) is not None

def get_latest_valid_run():
    """
    Trả về RUN_DIR và summary path hợp lệ nhất:
      - Bỏ DEMO, TEST, GITLEAKS
      - Chỉ lấy dạng RUN_VSP_FULL_EXT_YYYYmmdd_HHMMSS
    """
    out = get_out_dir()
    if not out.is_dir():
        return None, None

    candidates = sorted(
        [d for d in out.iterdir() if d.is_dir() and is_valid_run_name(d.name)],
        key=lambda p: p.name,
        reverse=True,
    )

    for d in candidates:
        summary = d / "report" / "summary_unified.json"
        if summary.is_file():
            return d, summary

    return None, None


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
