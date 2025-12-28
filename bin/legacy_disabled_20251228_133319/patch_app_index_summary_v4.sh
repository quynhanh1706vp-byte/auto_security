#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

# Tìm đúng block index hiện tại (bắt đầu từ @app.route("/", methods=["GET"])
start = code.find('@app.route("/", methods=["GET"])')
if start == -1:
    print("[ERR] Không tìm thấy @app.route(\"/\", methods=[\"GET\"]) trong app.py")
    sys.exit(1)

# Kết thúc: route kế tiếp hoặc if __name__ == "__main__"
next_route = code.find('\n@app.route', start + 1)
if next_route == -1:
    next_route = code.find('\nif __name__ == "__main__"', start + 1)
if next_route == -1:
    next_route = len(code)

before = code[:start]
after = code[next_route:]

new_block = textwrap.dedent("""
@app.route("/", methods=["GET"])
def index():
    \"""
    Dashboard chính: đọc RUN_* mới nhất trong out/ và đẩy số liệu
    lên template index.html (UI mới).
    \"""
    import json, datetime
    from pathlib import Path
    from collections import Counter

    ROOT = Path("/home/test/Data/SECURITY_BUNDLE")
    OUT = ROOT / "out"

    total_findings = 0
    crit_count = high_count = medium_count = low_count = 0
    last_run_id = "RUN_YYYYmmdd_HHMMSS"
    last_updated = "—"

    def pick_run_dirs(out_dir: Path):
        runs = []
        if not out_dir.is_dir():
            return runs
        for p in out_dir.iterdir():
            if not p.is_dir():
                continue
            name = p.name
            if not name.startswith("RUN_"):
                continue
            # RUN_YYYYmmdd_HHMMSS = 19 ký tự
            if len(name) != 19:
                continue
            date_part = name[4:12]
            time_part = name[13:]
            if not (date_part.isdigit() and time_part.isdigit()):
                continue
            runs.append(p)
        runs.sort(key=lambda x: x.name)
        return runs

    def load_from_summary_dict(data: dict):
        nonlocal total_findings, crit_count, high_count, medium_count, low_count

        # Có thể là { "summary_all": {...} } hoặc {...} luôn
        if "summary_all" in data and isinstance(data["summary_all"], dict):
            data = data["summary_all"]

        total_findings = (
            data.get("total")
            or data.get("total_findings")
            or data.get("findings_total")
            or 0
        )

        sev = (
            data.get("by_severity")
            or data.get("severity_buckets")
            or data.get("severity")
            or {}
        )

        crit_count = int(sev.get("CRITICAL", 0) or 0)
        high_count = int(sev.get("HIGH", 0) or 0)
        medium_count = int(sev.get("MEDIUM", 0) or 0)
        low_count = (
            int(sev.get("LOW", 0) or 0)
            + int(sev.get("INFO", 0) or 0)
            + int(sev.get("UNKNOWN", 0) or 0)
        )

    def load_from_findings_list(items):
        nonlocal total_findings, crit_count, high_count, medium_count, low_count
        total_findings = len(items)
        c = Counter()
        for item in items:
            if not isinstance(item, dict):
                continue
            sev = (item.get("severity") or item.get("sev") or "").upper()
            c[sev] += 1
        crit_count = c.get("CRITICAL", 0)
        high_count = c.get("HIGH", 0)
        medium_count = c.get("MEDIUM", 0)
        low_count = c.get("LOW", 0) + c.get("INFO", 0) + c.get("UNKNOWN", 0)

    runs = pick_run_dirs(OUT)
    if runs:
        last = runs[-1]
        last_run_id = last.name
        dt = datetime.datetime.fromtimestamp(last.stat().st_mtime)
        last_updated = dt.strftime("%Y-%m-%d %H:%M:%S")

        # Danh sách các JSON có thể có
        candidates = [
            last / "summary_unified.json",
            last / "summary.json",
            last / "report" / "summary_unified.json",
            last / "report" / "summary.json",
            last / "findings_unified.json",
            last / "report" / "findings_unified.json",
            last / "report" / "findings.json",
        ]

        picked = None
        for p in candidates:
            if p.is_file():
                picked = p
                break

        if picked is not None:
            try:
                with picked.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                print(f"[INFO][INDEX] Dùng dữ liệu từ: {picked}")

                if isinstance(data, dict):
                    load_from_summary_dict(data)
                elif isinstance(data, list):
                    load_from_findings_list(data)
                else:
                    print("[WARN][INDEX] JSON không phải dict/list, giữ 0.")
            except Exception as e:
                print(f"[WARN][INDEX] Lỗi đọc {picked}: {e}")

    print(f"[INFO][INDEX] RUN={last_run_id}, total={total_findings}, "
          f"C={crit_count}, H={high_count}, M={medium_count}, L={low_count}")

    return render_template(
        "index.html",
        total_findings=total_findings,
        crit_count=crit_count,
        high_count=high_count,
        medium_count=medium_count,
        low_count=low_count,
        last_run_id=last_run_id,
        last_updated=last_updated,
    )
""").lstrip("\\n")

code_new = before + new_block + "\\n\\n" + after
path.write_text(code_new, encoding="utf-8")
print("[OK] Đã thay thế index() bằng phiên bản v4 – đọc nhiều kiểu JSON và log [INFO][INDEX].")
PY
