from pathlib import Path
import json, os
from collections import Counter

from app import app
from flask import request, jsonify  # app gốc từ app.py

ROOT = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
OUT_DIR = ROOT / "out"


def _latest_run_dir():
    if not OUT_DIR.is_dir():
        return None
    latest = None
    for name in sorted(os.listdir(OUT_DIR)):
        if name.startswith("RUN_2"):
            latest = name
    if not latest:
        return None
    return OUT_DIR / latest


def _load_summary(latest_run_dir):
    if latest_run_dir is None:
        return None
    summary_path = latest_run_dir / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return None
    try:
        with summary_path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _load_findings(latest_run_dir):
    if latest_run_dir is None:
        return []
    report_dir = latest_run_dir / "report"
    candidates = [
        report_dir / "findings_unified.json",
        latest_run_dir / "findings_unified.json",
    ]
    findings_path = None
    for c in candidates:
        if c.is_file():
            findings_path = c
            break
    if findings_path is None:
        return []
    try:
        with findings_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return []
    if isinstance(data, dict) and "findings" in data:
        return data["findings"]
    if isinstance(data, list):
        return data
    return []


def _build_dashboard_data():
    latest_run_dir = _latest_run_dir()
    default = {
        "run": None,
        "total": 0,
        "critical": 0,
        "high": 0,
        "medium": 0,
        "low": 0,
        "info": 0,
        "buckets": {
            "CRITICAL": 0,
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "INFO": 0,
        },
    }
    if latest_run_dir is None:
        return default

    run_name = latest_run_dir.name
    summary = _load_summary(latest_run_dir)
    if summary is None:
        default["run"] = run_name
        return default

    def g(d, *keys, default=0):
        for k in keys:
            if k in d and d[k] is not None:
                return d[k]
        return default

    crit = g(summary, "critical", "crit", "C")
    high = g(summary, "high", "H")
    med = g(summary, "medium", "M")
    low = g(summary, "low", "L")
    info = g(summary, "info", "I")
    total = summary.get("total")
    if total is None:
        total = crit + high + med + low + info

    return {
        "run": run_name,
        "total": total,
        "critical": crit,
        "high": high,
        "medium": med,
        "low": low,
        "info": info,
        "buckets": {
            "CRITICAL": crit,
            "HIGH": high,
            "MEDIUM": med,
            "LOW": low,
            "INFO": info,
        },
    }


def _build_top_risks():
    latest_run_dir = _latest_run_dir()
    result = {
        "run": None,
        "total": 0,
        "buckets": {
            "CRITICAL": 0,
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "INFO": 0,
        },
        "top_risks": [],
    }
    if latest_run_dir is None:
        return result

    run_name = latest_run_dir.name
    result["run"] = run_name

    summary = _load_summary(latest_run_dir)
    if summary is not None:
        def g(d, *keys, default=0):
            for k in keys:
                if k in d and d[k] is not None:
                    return d[k]
            return default
        crit = g(summary, "critical", "crit", "C")
        high = g(summary, "high", "H")
        med = g(summary, "medium", "M")
        low = g(summary, "low", "L")
        info = g(summary, "info", "I")
        result["buckets"] = {
            "CRITICAL": crit,
            "HIGH": high,
            "MEDIUM": med,
            "LOW": low,
            "INFO": info,
        }
        result["total"] = crit + high + med + low + info

    findings = _load_findings(latest_run_dir)
    if not findings:
        return result

    def norm_sev(raw):
        if not raw:
            return "INFO"
        s = str(raw).upper()
        if s.startswith("CRIT"):
            return "CRITICAL"
        if s.startswith("HI"):
            return "HIGH"
        if s.startswith("MED"):
            return "MEDIUM"
        if s.startswith("LO"):
            return "LOW"
        if s.startswith("INFO") or s.startswith("INFORMATIONAL"):
            return "INFO"
        return "INFO"

    sev_counter = Counter(result["buckets"])
    top_candidates = []

    for f in findings:
        sev = (
            f.get("severity")
            or f.get("sev")
            or f.get("severity_norm")
            or f.get("severity_normalized")
            or f.get("level")
            or "INFO"
        )
        s = norm_sev(sev)
        sev_counter[s] += 1

        if s in ("CRITICAL", "HIGH"):
            tool = f.get("tool") or f.get("source") or f.get("engine") or "?"
            rule = f.get("rule_id") or f.get("id") or f.get("check_id") or "?"
            location = (
                f.get("location")
                or f.get("path")
                or f.get("file")
                or ""
            )
            line = f.get("line") or f.get("start_line") or None
            if line:
                location = f"{location}:{line}" if location else str(line)
            top_candidates.append({
                "severity": s,
                "tool": tool,
                "rule": rule,
                "location": location,
            })

    for k in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]:
        sev_counter.setdefault(k, 0)

    result["buckets"] = dict(sev_counter)
    result["total"] = sum(sev_counter.values())

    weight = {"CRITICAL": 2, "HIGH": 1}
    top_candidates.sort(
        key=lambda x: (weight.get(x["severity"], 0), x.get("tool") or ""),
        reverse=True,
    )
    result["top_risks"] = top_candidates[:10]

    return result


# === Gắn/override endpoint cho /api/dashboard_data ===
def api_dashboard_data_impl():
    return _build_dashboard_data()


if "api_dashboard_data" in app.view_functions:
    app.view_functions["api_dashboard_data"] = api_dashboard_data_impl
else:
    app.add_url_rule(
        "/api/dashboard_data",
        "api_dashboard_data",
        api_dashboard_data_impl,
        methods=["GET"],
    )


# === Gắn/override endpoint cho /api/top_risks_v2 và /api/top_risks ===
def api_top_risks_v2_impl():
    return _build_top_risks()


if "api_top_risks_v2" in app.view_functions:
    app.view_functions["api_top_risks_v2"] = api_top_risks_v2_impl
else:
    app.add_url_rule(
        "/api/top_risks_v2",
        "api_top_risks_v2",
        api_top_risks_v2_impl,
        methods=["GET"],
    )


def api_top_risks_impl():
    return _build_top_risks()


if "api_top_risks" in app.view_functions:
    app.view_functions["api_top_risks"] = api_top_risks_impl
else:
    app.add_url_rule(
        "/api/top_risks",
        "api_top_risks",
        api_top_risks_impl,
        methods=["GET"],
    )



@app.route("/api/run_scan_simple", methods=["POST"])
def api_run_scan_simple():
    """
    Gọi bin/run_all_tools_v2.sh với SRC lấy từ Dashboard.
    Chạy nền, trả JSON báo đã nhận request.
    """
    import os
    from subprocess import Popen
    from pathlib import Path as _Path

    try:
        payload = request.get_json(force=True, silent=True) or {}
    except Exception:
        payload = {}

    src = payload.get("src_folder") or request.form.get("src_folder") or ""
    target = payload.get("target_url") or request.form.get("target_url") or ""

    src = (src or "").strip()
    if not src:
        return jsonify({"ok": False, "error": "src_folder is required"}), 400

    # Chuẩn hóa path: hỗ trợ ~/..., /..., và thiếu dấu / đầu
    if src.startswith("~"):
        src_path = _Path(os.path.expanduser(src))
    elif src.startswith("/"):
        src_path = _Path(src)
    else:
        src_path = _Path("/" + src.lstrip("/"))

    if not src_path.exists() or not src_path.is_dir():
        return jsonify({"ok": False, "error": f"SRC folder not found: {src_path}"}), 400

    ROOT = _Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    env = os.environ.copy()
    env["SRC"] = str(src_path)
    if target:
        env["TARGET_URL"] = str(target)

    log_dir = ROOT / "out" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "run_scan_simple.log"

    with log_file.open("ab") as f:
        Popen(
            ["bash", "bin/run_all_tools_v2.sh"],
            cwd=str(ROOT),
            env=env,
            stdout=f,
            stderr=f,
        )

    return jsonify({"ok": True, "src": str(src_path)})



def _serialize_runs_brief():
    runs = []
    try:
        out_dir = OUT_DIR
    except NameError:
        from pathlib import Path as _Path
        out_dir = _Path(__file__).resolve().parent.parent / "out"

    if not out_dir.is_dir():
        return []

    for d in sorted(out_dir.glob("RUN_2*")):
        if not d.is_dir():
            continue
        name = d.name
        if name.startswith("RUN_GITLEAKS_EXT_") or name.startswith("RUN_DEMO_"):
            continue
        report_dir = d / "report"
        summary_path = report_dir / "summary_unified.json"
        if not summary_path.is_file():
            continue
        try:
            with summary_path.open("r", encoding="utf-8") as f:
                s = json.load(f)
        except Exception:
            continue
        total = s.get("total")
        crit  = s.get("critical") or s.get("crit") or s.get("C") or 0
        high  = s.get("high") or s.get("H") or 0
        med   = s.get("medium") or s.get("M") or 0
        low   = s.get("low") or s.get("L") or 0
        mt = d.stat().st_mtime
        from datetime import datetime
        ts = datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M:%S")
        runs.append({
            "run": name,
            "time": ts,
            "total": total,
            "critical": crit,
            "high": high,
            "medium": med,
            "low": low,
        })

    runs.sort(key=lambda x: x.get("run") or "", reverse=True)
    return runs


def api_runs_brief_impl():
    return _serialize_runs_brief()


if "api_runs_brief" in app.view_functions:
    app.view_functions["api_runs_brief"] = api_runs_brief_impl
else:
    app.add_url_rule(
        "/api/runs_brief",
        "api_runs_brief",
        api_runs_brief_impl,
        methods=["GET"],
    )


def api_runs_impl():
    return _serialize_runs_brief()


if "api_runs" in app.view_functions:
    app.view_functions["api_runs"] = api_runs_impl
else:
    app.add_url_rule(
        "/api/runs",
        "api_runs",
        api_runs_impl,
        methods=["GET"],
    )


TOOL_CFG_PATH = Path(__file__).resolve().parent / "tool_config.json"


def _load_tool_config_summary():
    cfg_path = TOOL_CFG_PATH
    if not cfg_path.is_file():
        return {"tools": []}

    try:
        with cfg_path.open("r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        return {"tools": []}

    # Nếu là dict có key 'tools' thì lấy ra
    if isinstance(cfg, dict):
        if "tools" in cfg and isinstance(cfg["tools"], list):
            items = cfg["tools"]
        elif "config" in cfg and isinstance(cfg["config"], list):
            items = cfg["config"]
        else:
            items = list(cfg.values()) if isinstance(list(cfg.values())[0], dict) else []
    elif isinstance(cfg, list):
        items = cfg
    else:
        items = []

    rows = []

    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        name = (
            item.get("tool")
            or item.get("name")
            or item.get("id")
            or f"tool_{idx+1}"
        )

        def _b(val):
            if isinstance(val, bool):
                return val
            if isinstance(val, (int, float)):
                return val != 0
            if isinstance(val, str):
                return val.strip().lower() in ("1", "true", "yes", "y", "on")
            return False

        enabled = (
            _b(item.get("enabled"))
            or _b(item.get("enable"))
            or _b(item.get("ENABLED"))
            or _b(item.get("ENABLE"))
        )

        level = (
            item.get("profile")
            or item.get("level")
            or item.get("mode")
            or item.get("severity")
            or ""
        )

        modes = []
        for key, label in [
            ("mode_offline", "Offline"),
            ("mode_online", "Online"),
            ("mode_ci", "CI/CD"),
            ("offline", "Offline"),
            ("online", "Online"),
            ("ci_cd", "CI/CD"),
            ("ci", "CI/CD"),
        ]:
            if key in item and _b(item.get(key)):
                modes.append(label)

        modes_str = ", ".join(sorted(set(modes))) if modes else ""
        rows.append({
            "tool": name,
            "enabled": enabled,
            "level": level,
            "modes": modes_str,
        })

    return {"tools": rows}


def api_tools_by_config_impl():
    return _load_tool_config_summary()


if "api_tools_by_config" in app.view_functions:
    app.view_functions["api_tools_by_config"] = api_tools_by_config_impl
else:
    app.add_url_rule(
        "/api/tools_by_config",
        "api_tools_by_config",
        api_tools_by_config_impl,
        methods=["GET"],
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8905, debug=True)

# === AUTO PATCH V3: API /api/runs_v2 + /api/tools_config_v2 ===
import json as _json_v3
from pathlib import Path as _Path_v3
from datetime import datetime as _dt_v3

try:
    app  # type: ignore[name-defined]
except NameError:
    # nếu không có biến app thì thôi, tránh lỗi import
    pass
else:
    def _sb_v3_get_out_dir():
        # gốc = thư mục SECURITY_BUNDLE
        return _Path_v3(__file__).resolve().parent.parent / "out"

    def _sb_v3_serialize_runs():
        out_dir = _sb_v3_get_out_dir()
        runs = []
        if not out_dir.is_dir():
            return runs

        for d in sorted(out_dir.glob("RUN_2*")):
            if not d.is_dir():
                continue
            name = d.name
            if name.startswith("RUN_GITLEAKS_EXT_") or name.startswith("RUN_DEMO_"):
                continue
            report_dir = d / "report"
            summary_path = report_dir / "summary_unified.json"
            if not summary_path.is_file():
                continue
            try:
                with summary_path.open("r", encoding="utf-8") as f:
                    s = _json_v3.load(f)
            except Exception:
                continue

            total = s.get("total")
            crit  = s.get("critical") or s.get("crit") or s.get("C") or 0
            high  = s.get("high") or s.get("H") or 0
            med   = s.get("medium") or s.get("M") or 0
            low   = s.get("low") or s.get("L") or 0

            mt = d.stat().st_mtime
            ts = _dt_v3.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M:%S")

            runs.append({
                "run": name,
                "time": ts,
                "total": total,
                "critical": crit,
                "high": high,
                "medium": med,
                "low": low,
            })

        runs.sort(key=lambda x: x.get("run") or "", reverse=True)
        return runs

    @app.route("/api/runs_v2", methods=["GET"])
    def api_runs_v2():
        return _sb_v3_serialize_runs()

    def _sb_v3_load_tool_config():
        cfg_path = _Path_v3(__file__).resolve().parent / "tool_config.json"
        if not cfg_path.is_file():
            return {"tools": []}
        try:
            with cfg_path.open("r", encoding="utf-8") as f:
                cfg = _json_v3.load(f)
        except Exception:
            return {"tools": []}

        if isinstance(cfg, dict):
            if isinstance(cfg.get("tools"), list):
                items = cfg["tools"]
            elif isinstance(cfg.get("config"), list):
                items = cfg["config"]
            else:
                vals = list(cfg.values())
                items = vals if vals and isinstance(vals[0], dict) else []
        elif isinstance(cfg, list):
            items = cfg
        else:
            items = []

        rows = []

        def _b(val):
            if isinstance(val, bool):
                return val
            if isinstance(val, (int, float)):
                return val != 0
            if isinstance(val, str):
                return val.strip().lower() in ("1", "true", "yes", "y", "on")
            return False

        for idx, item in enumerate(items):
            if not isinstance(item, dict):
                continue

            name = (
                item.get("tool")
                or item.get("name")
                or item.get("id")
                or f"tool_{idx+1}"
            )

            enabled = (
                _b(item.get("enabled"))
                or _b(item.get("enable"))
                or _b(item.get("ENABLED"))
                or _b(item.get("ENABLE"))
            )

            level = (
                item.get("profile")
                or item.get("level")
                or item.get("mode")
                or item.get("severity")
                or ""
            )

            modes = []
            for key, label in [
                ("mode_offline", "Offline"),
                ("mode_online", "Online"),
                ("mode_ci", "CI/CD"),
                ("offline", "Offline"),
                ("online", "Online"),
                ("ci_cd", "CI/CD"),
                ("ci", "CI/CD"),
            ]:
                if key in item and _b(item.get(key)):
                    modes.append(label)

            modes_str = ", ".join(sorted(set(modes))) if modes else ""

            rows.append({
                "tool": name,
                "enabled": enabled,
                "level": level,
                "modes": modes_str,
            })

        return {"tools": rows}

    @app.route("/api/tools_config_v2", methods=["GET"])
    def api_tools_config_v2():
        return _sb_v3_load_tool_config()

# === END AUTO PATCH V3 ===

