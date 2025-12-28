import json
import pathlib
from typing import Optional

# ROOT = thư mục gốc SECURITY_BUNDLE
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "out"
CONFIG_DIR = ROOT / "ui" / "config"
PIN_FILE = CONFIG_DIR / "vsp_dashboard_pin_v1.json"


def _has_summary(run_id: str) -> bool:
    run_dir = OUT_DIR / run_id
    return (run_dir / "report" / "summary_unified.json").is_file()


def pick_pinned_run() -> Optional[str]:
    """
    Ưu tiên run được pin trong vsp_dashboard_pin_v1.json nếu:
      - tồn tại
      - có summary_unified.json
    """
    try:
        data = json.loads(PIN_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except Exception:
        return None

    run_id = data.get("run_id")
    if not run_id:
        return None
    if not _has_summary(run_id):
        return None
    return run_id


def pick_latest_full_ext() -> Optional[str]:
    """
    Tự động chọn run mới nhất:
      - tên bắt đầu RUN_VSP_
      - có FULL_EXT trong tên
      - có report/summary_unified.json
    """
    candidates = []
    if not OUT_DIR.is_dir():
        return None

    for p in OUT_DIR.iterdir():
        if not p.is_dir():
            continue
        name = p.name
        if not name.startswith("RUN_VSP_"):
            continue
        if "FULL_EXT" not in name:
            continue
        summary = p / "report" / "summary_unified.json"
        if not summary.is_file():
            continue
        mtime = summary.stat().st_mtime
        candidates.append((mtime, name))

    if not candidates:
        return None

    candidates.sort(reverse=True)
    return candidates[0][1]


def pick_dashboard_run(default: Optional[str] = None) -> Optional[str]:
    """
    Thứ tự ưu tiên:
      1. Run pin trong vsp_dashboard_pin_v1.json
      2. Run FULL_EXT mới nhất có summary_unified.json
      3. default (nếu caller truyền vào)
    """
    return pick_pinned_run() or pick_latest_full_ext() or default
