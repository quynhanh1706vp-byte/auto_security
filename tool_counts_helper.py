import os, csv, json

def _norm_key(s: str) -> str:
    if not s:
        return ""
    return s.strip().lower().replace(" ", "").replace("-", "").replace("_", "")

def _canon_tool(raw: str) -> str:
    k = _norm_key(raw)
    mapping = {
        "gitleaks": "gitleaks",
        "semgrep": "semgrep",
        "bandit": "bandit",
        "trivysecret": "trivysecret",
        "trivysecrets": "trivysecret",
        "trivymisconfig": "trivymisconfig",
        "trivymisconfiguration": "trivymisconfig",
        "trivyvuln": "trivyvuln",
        "trivyfs": "trivyvuln",
        "trivyvulnerability": "trivyvuln",
        "grype": "grype",
    }
    return mapping.get(k, "")

def load_tool_counts_from_csv(run_dir: str) -> dict:
    """
    Đọc reports/findings_unified.csv và trả về:
      { 'gitleaks': 0, 'semgrep': 20, 'bandit': 2, 'trivyvuln': 34, 'grype': 4, ... }
    """
    counts = {
        "gitleaks": 0,
        "semgrep": 0,
        "bandit": 0,
        "trivysecret": 0,
        "trivymisconfig": 0,
        "trivyvuln": 0,
        "grype": 0,
    }
    csv_path = os.path.join(run_dir, "reports", "findings_unified.csv")
    if not os.path.isfile(csv_path):
        return counts

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_tool = (
                row.get("tool")
                or row.get("Tool")
                or row.get("TOOL")
                or ""
            )
            canon = _canon_tool(raw_tool)
            if canon in counts:
                counts[canon] += 1

    return counts

def build_tool_rows(config_path: str, run_dir: str):
    """
    Đọc tool_config.json (cấu hình UI), merge thêm COUNT từ findings_unified.csv.
    Trả về list row đã có trường 'count'.
    """
    if os.path.isfile(config_path):
        with open(config_path, encoding="utf-8") as f:
            config_rows = json.load(f)
    else:
        config_rows = []

    counts = load_tool_counts_from_csv(run_dir)
    result = []

    for row in config_rows:
        # cố gắng lấy tên tool hiển thị trong bảng
        label = row.get("tool") or row.get("name") or row.get("id") or ""
        canon = _canon_tool(label)
        row = dict(row)  # copy ra để không sửa bản gốc
        if canon:
            row["count"] = counts.get(canon, 0)
        else:
            # fallback: nếu không map được, giữ nguyên hoặc =0
            row.setdefault("count", 0)
        result.append(row)

    return result
