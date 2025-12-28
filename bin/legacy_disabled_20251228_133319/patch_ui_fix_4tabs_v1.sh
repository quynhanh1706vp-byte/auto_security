#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/app.py"

echo "[i] ROOT = $ROOT"
cd "$ROOT"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py ở $APP" >&2
  exit 1
fi

cp "$APP" "${APP}.bak_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
import pathlib, textwrap, re, json

path = pathlib.Path("app.py")
data = path.read_text(encoding="utf-8")

# -------------------------------------------------------------------
# 1) Thêm helper load last_summary_unified.json + findings.json
# -------------------------------------------------------------------
if "SECURITY_BUNDLE JSON HELPERS V2" not in data:
    helper_block = textwrap.dedent("""
    # ======= SECURITY_BUNDLE JSON HELPERS V2 =======
    from pathlib import Path
    import json

    ROOT = Path("/home/test/Data/SECURITY_BUNDLE").resolve()
    OUT_DIR = ROOT / "out"
    STATIC_DIR = ROOT / "ui" / "static"

    SEV_ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "INFO": 4}


    def _load_last_summary_and_findings():
        \"\"\"Load last summary_unified.json + findings.json.

        Ưu tiên:
        - ui/static/last_summary_unified.json
        - ui/static/last_findings.json
        Nếu không có thì tìm RUN_* mới nhất trong out/ có đủ 2 file.
        \"\"\"
        summary_path = STATIC_DIR / "last_summary_unified.json"
        findings_path = STATIC_DIR / "last_findings.json"

        run_dir = None
        run_id = None

        if not summary_path.exists() or not findings_path.exists():
            candidates = []
            if OUT_DIR.exists():
                for d in OUT_DIR.iterdir():
                    if not d.is_dir():
                        continue
                    name = d.name
                    if not name.startswith("RUN_"):
                        continue
                    s = d / "report" / "summary_unified.json"
                    f = d / "report" / "findings.json"
                    if s.exists() and f.exists():
                        candidates.append((d.stat().st_mtime, d, s, f))
            if not candidates:
                return None
            candidates.sort(reverse=True)
            _, run_dir, summary_path, findings_path = candidates[0]
            run_id = run_dir.name

        with summary_path.open(encoding="utf-8") as fh:
            summary = json.load(fh)
        with findings_path.open(encoding="utf-8") as fh:
            findings = json.load(fh)

        if not run_id:
            run_id = summary.get("run_id") or summary.get("run") or "UNKNOWN"

        return {
            "run_id": run_id,
            "run_dir": str(run_dir) if run_dir else None,
            "summary_path": str(summary_path),
            "findings_path": str(findings_path),
            "summary": summary,
            "findings": findings,
        }
    # ======= END HELPERS V2 =======
    """).lstrip("\n")
    data = data + "\n\n" + helper_block
    print("[INFO] Added helper block.")
else:
    print("[INFO] Helper block already present.")


def patch_route(pattern, new_block, label):
    global data
    m = re.search(pattern, data, flags=re.DOTALL)
    if not m:
        print(f"[WARN] Cannot find route for {label} (giữ nguyên code cũ).")
        return
    data = data[:m.start()] + textwrap.dedent(new_block).lstrip("\n") + "\n\n" + data[m.end():]
    print(f"[OK] Patched route {label}.")


# -------------------------------------------------------------------
# 2) Patch /runs  -> đọc summary_unified.json cho từng RUN_*
# -------------------------------------------------------------------
patch_route(
    r"@app\\.route\\(\"/runs\"[^\n]*\\)\\s+def\\s+runs\\([^)]*\\):.*?(?=\\n@app\\.route|\\nif __name__ == \"__main__\"|$)",
    '''
    @app.route("/runs", methods=["GET"])
    def runs():
        """
        Runs & Reports – list toàn bộ RUN_* có summary_unified.json.
        """
        rows = []
        from pathlib import Path as _Path
        out_dir = _Path("/home/test/Data/SECURITY_BUNDLE") / "out"

        if out_dir.exists():
            for d in out_dir.iterdir():
                if not d.is_dir():
                    continue
                name = d.name
                if not name.startswith("RUN_"):
                    continue
                s = d / "report" / "summary_unified.json"
                if not s.exists():
                    continue
                try:
                    with s.open(encoding="utf-8") as fh:
                        info = json.load(fh)
                except Exception:
                    continue

                by_sev = info.get("by_severity", {}) or {}
                rows.append(
                    {
                        "run": name,
                        "total": info.get("total", 0),
                        "C": by_sev.get("CRITICAL", 0),
                        "H": by_sev.get("HIGH", 0),
                        "M": by_sev.get("MEDIUM", 0),
                        "L": by_sev.get("LOW", 0),
                        "report_url": f"/pm_report/{name}/html",
                    }
                )

        rows.sort(key=lambda r: r["run"], reverse=True)
        # Trả thêm vài alias cho template cũ nếu có
        return render_template("runs.html", runs=rows, run_rows=rows, rows=rows)
    ''',
    "runs",
)

# -------------------------------------------------------------------
# 3) Patch /datasource -> dùng cùng cặp JSON với Dashboard
# -------------------------------------------------------------------
patch_route(
    r"@app\\.route\\(\"/datasource\"[^\n]*\\)\\s+def\\s+datasource\\([^)]*\\):.*?(?=\\n@app\\.route|\\nif __name__ == \"__main__\"|$)",
    '''
    @app.route("/datasource", methods=["GET"])
    def datasource():
        """
        Data Source – dùng cùng summary_unified.json + findings.json với Dashboard.
        """
        ctx = {
            "has_data": False,
            "run_dir": None,
            "summary_path": None,
            "findings_path": None,
            "sample_findings": [],
            "summary_total": 0,
            "summary_by_severity": [],
            "summary_by_tool": [],
            "by_severity": [],
            "by_tool": [],
            "raw_summary": "{}",
            "raw_findings": "[]",
            "raw_json_summary": "{}",
            "raw_json_findings": "[]",
        }

        data_last = _load_last_summary_and_findings()
        if data_last is None:
            return render_template("datasource.html", **ctx)

        summary = data_last["summary"]
        findings = data_last["findings"]

        ctx["has_data"] = True
        ctx["run_dir"] = data_last["run_dir"]
        ctx["summary_path"] = data_last["summary_path"]
        ctx["findings_path"] = data_last["findings_path"]

        sample = findings[:200]
        ctx["sample_findings"] = sample
        ctx["summary_total"] = summary.get("total", len(findings))

        by_sev_table = []
        by_sev = summary.get("by_severity", {}) or {}
        for key in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]:
            if key in by_sev:
                by_sev_table.append({"severity": key, "count": by_sev.get(key, 0)})
        ctx["summary_by_severity"] = by_sev_table
        ctx["by_severity"] = by_sev_table

        by_tool_table = []
        for tool_name, info in (summary.get("tools") or {}).items():
            by_tool_table.append(
                {"tool": tool_name, "total": info.get("total", 0)}
            )
        ctx["summary_by_tool"] = by_tool_table
        ctx["by_tool"] = by_tool_table

        ctx["raw_summary"] = json.dumps(summary, indent=2, ensure_ascii=False)
        ctx["raw_findings"] = json.dumps(sample, indent=2, ensure_ascii=False)
        ctx["raw_json_summary"] = ctx["raw_summary"]
        ctx["raw_json_findings"] = ctx["raw_findings"]

        return render_template("datasource.html", **ctx)
    ''',
    "datasource",
)

# -------------------------------------------------------------------
# 4) Patch /settings -> đọc đúng cấu trúc tool_config.json
# -------------------------------------------------------------------
patch_route(
    r"@app\\.route\\(\"/settings\"[^\n]*\\)\\s+def\\s+settings\\([^)]*\\):.*?(?=\\n@app\\.route|\\nif __name__ == \"__main__\"|$)",
    '''
    @app.route("/settings", methods=["GET", "POST"])
    def settings():
        """
        Settings – đọc tool_config.json (list các tool) và render bảng.
        Hỗ trợ cả format:
        - [ {...}, {...} ]
        - { "tools": [ {...}, {...} ] }
        """
        cfg_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json")
        tools = []

        if cfg_path.exists():
            try:
                raw = json.loads(cfg_path.read_text(encoding="utf-8"))
                if isinstance(raw, dict) and isinstance(raw.get("tools"), list):
                    tools = raw["tools"]
                elif isinstance(raw, list):
                    tools = raw
            except Exception:
                tools = []

        raw_str = ""
        if tools:
            raw_str = json.dumps(tools, indent=2, ensure_ascii=False)

        # TODO: xử lý POST để Save changes nếu cần
        if request.method == "POST":
            pass

        return render_template(
            "settings.html",
            cfg_path=str(cfg_path),
            cfg_rows=tools,
            table_rows=tools,
            rows=tools,
            cfg_raw=raw_str,
        )
    ''',
    "settings",
)

path.write_text(data, encoding="utf-8")
print("[OK] app.py updated.")
PY

echo "[OK] Đã patch app.py (Runs & Reports / Settings / Data Source)."
