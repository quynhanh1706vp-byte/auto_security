#!/usr/bin/env python3
import os
import json
import datetime
import subprocess
from flask import Flask, request, redirect, url_for, render_template_string

# ====== CONFIG ======
ROOT = "/home/test/Data/SECURITY_BUNDLE"
OUT_DIR = os.path.join(ROOT, "out")
SCAN_WRAPPER = "/home/test/run_all_with_grype_fix.sh"
DEFAULT_SRC = "/home/test/Data/Khach"
TOOL_CFG_PATH = os.path.join(ROOT, "ui", "tool_config.json")

app = Flask(__name__)

SEV_KEYS = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]

# ====== SEVERITY HELPERS (PYTHON) ======
def norm_sev_py(s: str) -> str:
    if not s:
        return "INFO"
    s = str(s).strip().upper()
    if "CRIT" in s:
        return "CRITICAL"
    if "HIGH" in s:
        return "HIGH"
    if "MED" in s:
        return "MEDIUM"
    if "LOW" in s:
        return "LOW"
    if "INFO" in s or "NEGLIGIBLE" in s or "UNKNOWN" in s:
        return "INFO"
    return s

# ====== TOOL CONFIG (PYTHON) ======
def default_tool_config():
    # Cấu hình mặc định an toàn
    return {
        "profiles": {
            "quick": {
                "Semgrep":        True,
                "Gitleaks":       True,
                "Bandit":         False,
                "TrivyVuln":      True,
                "TrivyMisconfig": False,
                "TrivySecret":    False,
                "Grype":          False,
            },
            "standard": {
                "Semgrep":        True,
                "Gitleaks":       True,
                "Bandit":         True,
                "TrivyVuln":      True,
                "TrivyMisconfig": True,
                "TrivySecret":    True,
                "Grype":          True,
            },
            "aggr": {
                "Semgrep":        True,
                "Gitleaks":       True,
                "Bandit":         True,
                "TrivyVuln":      True,
                "TrivyMisconfig": True,
                "TrivySecret":    True,
                "Grype":          True,
            },
        }
    }

def load_tool_config():
    cfg = default_tool_config()
    try:
        if os.path.exists(TOOL_CFG_PATH):
            with open(TOOL_CFG_PATH, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and isinstance(data.get("profiles"), dict):
                for prof, tools in data["profiles"].items():
                    if not isinstance(tools, dict):
                        continue
                    cfg.setdefault("profiles", {}).setdefault(prof, {})
                    for t, v in tools.items():
                        cfg["profiles"][prof][t] = bool(v)
    except Exception:
        # Nếu lỗi, cứ dùng default, tránh crash
        pass
    return cfg

def save_tool_config(profiles: dict):
    cfg = {"profiles": {}}
    for p in ("quick", "standard", "aggr"):
        tools = profiles.get(p, {})
        if not isinstance(tools, dict):
            tools = {}
        cfg["profiles"][p] = {str(k): bool(v) for k, v in tools.items()}
    os.makedirs(os.path.dirname(TOOL_CFG_PATH), exist_ok=True)
    with open(TOOL_CFG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return cfg

# ====== SUMMARY / FINDINGS (PYTHON) ======
def build_summary(findings, run_dir=None):
    by = {k: 0 for k in SEV_KEYS}
    per_tool = {}
    for r in findings or []:
        sev = norm_sev_py(r.get("severity", ""))
        if sev not in by:
            by[sev] = 0
        by[sev] += 1

        tool = r.get("tool") or r.get("category") or "Unknown"
        t = per_tool.setdefault(tool, {"total": 0, "by_severity": {}})
        t["total"] += 1
        bs = t["by_severity"]
        bs[sev] = bs.get(sev, 0) + 1

    total = len(findings or [])
    project = os.path.basename(run_dir) if run_dir else "Uploaded"
    summary = {
        "project": project,
        "mode": "Offline / Aggressive",
        "last_scan": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "total": total,
        "by_severity_overall": by,
        "per_tool": per_tool,
    }
    return summary

def _load_findings_for_run(run_dir: str):
    rep = os.path.join(run_dir, "report")
    if not os.path.isdir(rep):
        return []
    # ưu tiên report/findings.json, fallback sang report/report/findings.json
    path1 = os.path.join(rep, "findings.json")
    path2 = os.path.join(rep, "report", "findings.json")
    path = path1 if os.path.exists(path1) else path2
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
        return []
    except Exception:
        return []

def load_last_run():
    if not os.path.isdir(OUT_DIR):
        return {}, [], {"project": "No RUN", "last_scan": "—"}

    runs = [
        os.path.join(OUT_DIR, d)
        for d in os.listdir(OUT_DIR)
        if d.startswith("RUN_") and os.path.isdir(os.path.join(OUT_DIR, d))
    ]
    if not runs:
        return {}, [], {"project": "No RUN", "last_scan": "—"}

    runs.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    run_dir = runs[0]
    findings = _load_findings_for_run(run_dir)
    summary = build_summary(findings, run_dir)
    meta = {
        "project": summary.get("project", "Unknown"),
        "last_scan": summary.get("last_scan", "—"),
    }
    return summary, findings, meta

def list_runs_meta(limit: int = 20):
    """Liệt kê các RUN_* gần nhất – đơn giản, tránh lỗi."""
    rows = []
    if not os.path.isdir(OUT_DIR):
        return rows

    runs = [
        os.path.join(OUT_DIR, d)
        for d in os.listdir(OUT_DIR)
        if d.startswith("RUN_") and os.path.isdir(os.path.join(OUT_DIR, d))
    ]
    runs.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    runs = runs[:limit]

    for run_dir in runs:
        run_id = os.path.basename(run_dir)
        meta_path = os.path.join(run_dir, "meta.json")
        meta = {}
        if os.path.exists(meta_path):
            try:
                with open(meta_path, encoding="utf-8") as f:
                    meta = json.load(f)
            except Exception:
                meta = {}

        src = meta.get("src") or meta.get("SRC") or "-"
        level = meta.get("level") or meta.get("LEVEL") or "-"
        # mode: offline/online nếu có NO_NET
        mode = meta.get("mode")
        if not mode:
            no_net = str(meta.get("NO_NET", "")).strip()
            if no_net == "1":
                mode = "offline"
            elif "NO_NET" in meta:
                mode = "online"
            else:
                mode = "-"

        findings = _load_findings_for_run(run_dir)
        total = len(findings or [])
        crit = sum(1 for r in findings if norm_sev_py(r.get("severity", "")) == "CRITICAL")
        high = sum(1 for r in findings if norm_sev_py(r.get("severity", "")) == "HIGH")
        mtime = datetime.datetime.fromtimestamp(os.path.getmtime(run_dir)).strftime("%Y-%m-%d %H:%M:%S")

        rows.append({
            "run_id": run_id,
            "src": src,
            "level": level,
            "mode": mode,
            "total": total,
            "critical": crit,
            "high": high,
            "mtime": mtime,
        })
    return rows

# ====== TEMPLATE HTML+JS (ổn định, không cần sửa thường xuyên) ======
TEMPLATE = r"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Security Scan Dashboard</title>
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <!-- Chart.js (sau này có thể tải về local, giờ cứ dùng CDN) -->
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    :root {
      --bg-main: #05070c;
      --bg-panel: #0d1117;
      --bg-panel-soft: #111827;
      --bg-badge: #1f2937;
      --border-soft: #1f2937;
      --text-main: #e5e7eb;
      --text-soft: #9ca3af;
      --text-softer: #6b7280;
      --accent: #3b82f6;
      --critical: #ef4444;
      --high: #f97316;
      --medium: #eab308;
      --low: #22c55e;
      --info: #38bdf8;
    }
    * { box-sizing: border-box; }
    html, body {
      margin:0; padding:0; height:100%;
      font-family: system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
      color: var(--text-main);
      background: radial-gradient(circle at top left,#111827 0,#020617 55%);
    }
    body { display:flex; }

    .sidebar {
      width: 260px;
      background:#020617;
      border-right: 1px solid #1f2937;
      padding: 20px 18px;
      display:flex;
      flex-direction:column;
      gap:24px;
    }
    .logo-row { display:flex; align-items:center; gap:12px; }
    .logo-icon {
      width:32px; height:32px; border-radius:999px;
      background: conic-gradient(from 180deg, #3b82f6, #22c55e, #eab308, #ef4444, #3b82f6);
      padding:2px;
    }
    .logo-inner {
      width:100%; height:100%; border-radius:999px;
      background:#020617;
      display:flex; align-items:center; justify-content:center;
      font-size:16px; font-weight:700; color:#f9fafb;
    }
    .logo-text-title {
      font-size:14px; font-weight:600;
      letter-spacing:0.08em; text-transform:uppercase; color:#9ca3af;
    }
    .logo-text-sub {
      font-size:11px; color:#4b5563;
      text-transform:uppercase; letter-spacing:0.18em;
    }

    .nav-section-label {
      font-size:11px; color:#4b5563;
      text-transform:uppercase; letter-spacing:0.18em;
      margin-bottom:4px;
    }
    .nav-list { list-style:none; padding:0; margin:0; display:flex; flex-direction:column; gap:4px;}
    .nav-item {
      display:flex; align-items:center; gap:10px;
      padding:8px 10px; border-radius:8px;
      color:#9ca3af; font-size:13px; cursor:pointer;
      transition:background 0.15s,color 0.15s;
    }
    .nav-item span.icon { width:18px; text-align:center; font-size:14px; }
    .nav-item.active {
      background: linear-gradient(135deg,#111827,#020617);
      color:#e5e7eb; border:1px solid #1d4ed8;
    }
    .nav-item:hover { background:#0f172a; color:#e5e7eb; }

    .sidebar-footer {
      margin-top:auto; padding-top:16px;
      border-top:1px solid #111827;
      font-size:11px; color:#4b5563;
    }
    .badge-offline {
      display:inline-flex; align-items:center; gap:6px;
      background:#111827; border-radius:999px;
      padding:4px 8px; margin-top:6px;
      border:1px solid #1f2937;
    }
    .dot-green {
      width:8px; height:8px; border-radius:999px;
      background:#22c55e; box-shadow:0 0 8px rgba(34,197,94,0.7);
    }

    .main {
      flex:1; display:flex; flex-direction:column;
      padding:18px 22px; overflow:hidden;
    }
    .main-header {
      display:flex; align-items:flex-start;
      justify-content:space-between; gap:16px;
      margin-bottom:16px;
    }
    .title-block h1 {
      margin:0; font-size:24px;
      letter-spacing:0.06em; text-transform:uppercase;
    }
    .title-subline {
      margin-top:6px; font-size:12px; color:#9ca3af;
    }
    .title-subline code {
      font-family:"JetBrains Mono","Fira Code",monospace;
      background:#020617; padding:2px 6px; border-radius:999px;
      border:1px solid #111827; color:#e5e7eb;
    }
    .tag-pill {
      display:inline-flex; align-items:center; gap:6px;
      padding:2px 8px; border-radius:999px;
      font-size:11px; background:#111827;
      border:1px solid #1f2937; margin-left:4px; color:#9ca3af;
    }
    .tag-dot { width:6px; height:6px; border-radius:999px; background:#22c55e;}
    .tag-dot.offline { background:#f97316;}

    .header-actions {
      display:flex; flex-direction:column;
      gap:8px; align-items:flex-end; min-width:320px;
    }
    .input-inline {
      display:flex; gap:8px; align-items:center; margin-bottom:4px;
    }
    .input-inline label {
      font-size:11px; color:#9ca3af;
      text-transform:uppercase; letter-spacing:0.16em;
    }
    .input-text {
      background:#020617; border-radius:999px;
      border:1px solid #1f2937;
      padding:6px 10px; color:#e5e7eb;
      font-size:12px; min-width:160px; max-width:260px;
    }
    .input-text::placeholder { color:#4b5563; }
    select.input-text { padding-right:22px; }

    .btn {
      border:none; border-radius:999px;
      padding:7px 14px; font-size:12px;
      display:inline-flex; align-items:center; gap:6px;
      cursor:pointer; background:linear-gradient(135deg,#3b82f6,#2563eb);
      color:#f9fafb;
      box-shadow:0 0 0 1px #1d4ed8, 0 10px 25px rgba(37,99,235,0.45);
      white-space:nowrap;
    }
    .btn-secondary {
      background:#020617; border:1px solid #1f2937;
      box-shadow:none; color:#e5e7eb;
    }
    .btn span.icon { font-size:14px; }

    .upload-row {
      display:flex; gap:6px; align-items:center;
      font-size:11px; color:#9ca3af;
    }
    .upload-row input[type="file"]{
      font-size:11px; max-width:180px; color:#9ca3af;
    }

    .content-scroll {
      flex:1; overflow:auto;
      padding-right:4px; padding-bottom:10px;
    }

    .grid {
      display:grid; grid-template-columns: minmax(0,3fr) minmax(0,2fr);
      gap:16px; margin-bottom:16px;
    }
    .card {
      background:#020617;
      border-radius:14px; padding:14px 16px;
      border:1px solid #111827;
      box-shadow:0 18px 40px rgba(0,0,0,0.65);
    }
    .card-header {
      display:flex; align-items:center; justify-content:space-between;
      margin-bottom:10px; gap:8px;
    }
    .card-title {
      font-size:13px; font-weight:600;
      letter-spacing:0.12em; text-transform:uppercase;
      color:#9ca3af;
    }
    .card-sub { font-size:11px; color:#6b7280; }

    .kpi-grid {
      display:grid; grid-template-columns: repeat(4,minmax(0,1fr));
      gap:10px;
    }
    .kpi-card {
      background:#020617;
      border-radius:12px; padding:10px 12px;
      border:1px solid #111827; position:relative; overflow:hidden;
    }
    .kpi-label {
      font-size:11px; color:#9ca3af;
      text-transform:uppercase; letter-spacing:0.16em;
    }
    .kpi-value { margin-top:6px; font-size:19px; font-weight:600; }
    .kpi-foot { margin-top:4px; font-size:11px; color:#6b7280; }
    .kpi-chip {
      position:absolute; right:10px; bottom:8px;
      font-size:10px; padding:2px 8px;
      border-radius:999px; background:#111827;
      color:#6b7280; border:1px solid #111827;
    }

    .chart-wrapper {
      background:#05070c;
      border-radius:12px;
      padding:16px 20px 8px;
      height:260px;
    }
    .chart-wrapper canvas {
      width:100% !important;
      height:100% !important;
    }

    table { border-collapse:collapse; width:100%; font-size:12px; }
    thead { background:#020617; }
    thead th {
      padding:7px 8px; text-align:left; font-weight:500;
      color:#9ca3af; border-bottom:1px solid #1f2937;
      position:sticky; top:0; background:#020617; z-index:1;
    }
    tbody tr:nth-child(even) { background:#050816; }
    tbody tr:nth-child(odd) { background:#020617; }
    tbody td {
      padding:6px 8px; border-bottom:1px solid #020617;
      color:#d1d5db; vertical-align:top;
    }

    .chip-sev {
      display:inline-flex; align-items:center;
      padding:2px 7px; border-radius:999px;
      font-size:11px; font-weight:500;
    }
    .chip-critical { background:rgba(239,68,68,0.1); color:#fecaca; border:1px solid rgba(239,68,68,0.6);}
    .chip-high { background:rgba(249,115,22,0.1); color:#fed7aa; border:1px solid rgba(249,115,22,0.6);}
    .chip-medium { background:rgba(234,179,8,0.07); color:#fef9c3; border:1px solid rgba(234,179,8,0.5);}
    .chip-low { background:rgba(34,197,94,0.08); color:#bbf7d0; border:1px solid rgba(34,197,94,0.6);}
    .chip-info { background:rgba(56,189,248,0.1); color:#bae6fd; border:1px solid rgba(56,189,248,0.6);}

    .chip-status {
      display:inline-flex; align-items:center;
      padding:2px 7px; border-radius:999px;
      font-size:11px; background:#020617;
      color:#a5b4fc; border:1px solid #1d4ed8;
    }

    .muted { color:#6b7280; }
    .mono { font-family:"JetBrains Mono","Fira Code",monospace; font-size:11px; }

    .pill-tool {
      display:inline-flex; align-items:center; gap:4px;
      padding:2px 7px; border-radius:999px;
      background:#020617; border:1px solid #111827;
      font-size:11px; color:#9ca3af;
    }
    .pill-dot { width:6px;height:6px;border-radius:999px;background:#3b82f6; }

    .hint { font-size:11px; color:#6b7280; margin-top:4px; }

    @media (max-width: 1040px) {
      .sidebar { display:none; }
      .main { padding:14px; }
      .grid { grid-template-columns: minmax(0,1fr); }
      .kpi-grid { grid-template-columns: repeat(2,minmax(0,1fr)); }
      .header-actions { align-items:flex-start; min-width:auto; }
    }
  </style>
</head>
<body>
  <aside class="sidebar">
    <div>
      <div class="logo-row">
        <div class="logo-icon"><div class="logo-inner">S</div></div>
        <div>
          <div class="logo-text-title">SECURITY BUNDLE</div>
          <div class="logo-text-sub">AUTO • OFFLINE • CI</div>
        </div>
      </div>
    </div>

    <div>
      <div class="nav-section-label">MAIN</div>
      <ul class="nav-list">
        <li class="nav-item active" data-view="scan"><span class="icon">▶</span><span>Scan Project</span></li>
        <li class="nav-item" data-view="runs"><span class="icon">📁</span><span>Runs &amp; Reports</span></li>
        <li class="nav-item" data-view="settings"><span class="icon">⚙️</span><span>Settings</span></li>
      </ul>
    </div>

    <div class="sidebar-footer">
      <div>Run mode</div>
      <div class="badge-offline">
        <div class="dot-green"></div>
        <span id="tagMode">Offline • Aggressive</span>
      </div>
      <div style="margin-top:10px;">
        <div>Last scan:</div>
        <div id="footLastScan" class="mono muted">{{ last_scan }}</div>
      </div>
    </div>
  </aside>

  <main class="main">
    <header class="main-header">
      <div class="title-block">
        <h1>SECURITY SCAN</h1>
        <div class="title-subline">
          Project:
          <code id="projectPath">{{ project }}</code>
          <span class="tag-pill">
            <span class="tag-dot"></span>
            <span id="tagTotal">0 findings</span>
          </span>
          <span class="tag-pill">
            <span class="tag-dot offline"></span>
            <span id="tagTools">Semgrep • Gitleaks • Bandit • Trivy • Grype</span>
          </span>
        </div>
      </div>

      <div class="header-actions">
        <form id="formScan" method="post" action="{{ url_for('run_scan') }}">
          <div class="input-inline">
            <label for="webUrlInput">TARGET URL</label>
            <input id="webUrlInput" name="target_url" class="input-text" type="text"
                   placeholder="https://app.example.com (optional)" />
          </div>
          <div class="upload-row" style="margin-bottom:4px;">
            <span>SRC:</span>
            <input id="srcPath" name="src_path" class="input-text" type="text"
                   value="{{ src_default }}" placeholder="/path/to/src" />
            <span>Profile:</span>
            <select name="profile" class="input-text">
              <option value="aggr" selected>Aggressive</option>
              <option value="standard">Standard</option>
              <option value="quick">Quick</option>
            </select>
            <span>Mode:</span>
            <select name="mode" class="input-text">
              <option value="offline" selected>Offline</option>
              <option value="online">Online</option>
            </select>
            <button class="btn" type="submit">
              <span class="icon">▶</span><span>Run scan</span>
            </button>
          </div>
        </form>

        <div class="upload-row">
          <span>Data source:</span>
          <button class="btn-secondary" id="btnReload" type="button">
            <span class="icon">⟳</span><span>Reload current RUN</span>
          </button>
        </div>
        <div class="upload-row">
          <span>Or upload JSON:</span>
          <input type="file" id="fileSummary" accept="application/json" />
          <input type="file" id="fileFindings" accept="application/json" />
          <button class="btn" id="btnUploadLoad" type="button">
            <span class="icon">⬆</span><span>Render from files</span>
          </button>
        </div>
        <div class="hint">
          • Mặc định load từ RUN mới nhất trong <code>out/RUN_*/report/</code>.<br/>
          • Có thể upload cặp <code>summary_unified.json</code> + <code>findings.json</code> của khách để xem nhanh.
        </div>
      </div>
    </header>

    <section class="content-scroll">
      <!-- VIEW: SCAN -->
      <section id="view-scan" class="view-section" data-view="scan">
        <div class="kpi-grid" style="margin-bottom:12px;">
          <div class="kpi-card">
            <div class="kpi-label">Total findings</div>
            <div id="kpiTotal" class="kpi-value">0</div>
            <div class="kpi-foot">Across all tools &amp; severities</div>
            <div class="kpi-chip" id="kpiProjectChip">{{ project }}</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-label">Critical / High</div>
            <div class="kpi-value">
              <span id="kpiCrit">0</span>
              <span style="font-size:13px;">•</span>
              <span id="kpiHigh">0</span>
            </div>
            <div class="kpi-foot">Critical • High findings</div>
            <div class="kpi-chip">Max severity: <span id="kpiTopSeverity">–</span></div>
          </div>
          <div class="kpi-card">
            <div class="kpi-label">Medium / Low</div>
            <div class="kpi-value">
              <span id="kpiMed">0</span>
              <span style="font-size:13px;">•</span>
              <span id="kpiLow">0</span>
            </div>
            <div class="kpi-foot">Medium • Low findings</div>
            <div class="kpi-chip">Noise bucket</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-label">Info notes</div>
            <div class="kpi-value" id="kpiInfo">0</div>
            <div class="kpi-foot">Best effort / informational</div>
            <div class="kpi-chip">Triaged later</div>
          </div>
        </div>

        <div class="grid">
          <div class="card">
            <div class="card-header">
              <div>
                <div class="card-title">Findings by Severity</div>
                <div class="card-sub">Number of findings per severity bucket</div>
              </div>
            </div>
            <div class="chart-wrapper">
              <canvas id="severityChart"></canvas>
            </div>
          </div>

          <div class="card">
            <div class="card-header">
              <div>
                <div class="card-title">Findings by Tool</div>
                <div class="card-sub">Aggregated for this run</div>
              </div>
            </div>
            <div style="max-height:210px; overflow:auto;">
              <table>
                <thead>
                  <tr>
                    <th style="width:28%;">Tool</th>
                    <th>Critical</th>
                    <th>High</th>
                    <th>Medium</th>
                    <th>Low</th>
                    <th>Info</th>
                    <th>Total</th>
                  </tr>
                </thead>
                <tbody id="tblToolsBody"></tbody>
              </table>
            </div>
          </div>
        </div>

        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title">Top 20 Findings</div>
              <div class="card-sub">Sorted by severity, then by tool</div>
            </div>
            <div class="muted" style="font-size:11px;">
              Showing 20 most severe items from unified <code>findings.json</code>
            </div>
          </div>
          <div style="max-height:320px; overflow:auto; border-radius:10px; border:1px solid #020617;">
            <table>
              <thead>
                <tr>
                  <th style="width:80px;">Severity</th>
                  <th style="width:80px;">Tool</th>
                  <th style="width:120px;">Rule ID</th>
                  <th style="width:220px;">File : Line</th>
                  <th>Description</th>
                  <th style="width:80px;">Status</th>
                </tr>
              </thead>
              <tbody id="tblTopBody"></tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- VIEW: RUNS -->
      <section id="view-runs" class="view-section" data-view="runs" style="display:none;">
        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title">Runs &amp; Reports</div>
              <div class="card-sub">Danh sách các lần scan (RUN_*) gần đây</div>
            </div>
          </div>
          <div style="max-height:380px; overflow:auto;">
            <table>
              <thead>
                <tr>
                  <th style="width:180px;">RUN ID</th>
                  <th style="width:150px;">Time</th>
                  <th>SRC</th>
                  <th style="width:80px;">Level</th>
                  <th style="width:80px;">Mode</th>
                  <th style="width:80px;">Total</th>
                  <th style="width:80px;">Crit</th>
                  <th style="width:80px;">High</th>
                </tr>
              </thead>
              <tbody>
              {% if runs_meta %}
                {% for r in runs_meta %}
                <tr>
                  <td class="mono">{{ r.run_id }}</td>
                  <td class="mono">{{ r.mtime }}</td>
                  <td class="mono">{{ r.src }}</td>
                  <td>{{ r.level or "-" }}</td>
                  <td>{{ r.mode or "-" }}</td>
                  <td>{{ r.total }}</td>
                  <td>{{ r.critical }}</td>
                  <td>{{ r.high }}</td>
                </tr>
                {% endfor %}
              {% else %}
                <tr>
                  <td colspan="8" class="muted">Chưa có RUN nào trong thư mục <code>out/</code>.</td>
                </tr>
              {% endif %}
              </tbody>
            </table>
          </div>
          <div class="hint">
            Mỗi RUN nằm tại: <code>out/RUN_YYYYmmdd_HHMMSS/</code>.<br/>
            Report HTML: <code>out/RUN_.../report/security_resilient.html</code>.
          </div>
        </div>
      </section>

      <!-- VIEW: SETTINGS -->
      <section id="view-settings" class="view-section" data-view="settings" style="display:none;">
        <div class="card">
          <div class="card-header">
            <div>
              <div class="card-title">Tool Profile Matrix</div>
              <div class="card-sub">Bật/tắt tool theo profile Quick / Standard / Aggressive</div>
            </div>
            <div class="muted" style="font-size:11px;">
              Thay đổi áp dụng cho lần scan tiếp theo (wrapper đọc <code>ui/static/tool_config.json</code>).
            </div>
          </div>
          <div style="max-height:360px; overflow:auto;">
            <table>
              <thead>
                <tr>
                  <th style="width:28%;">Tool</th>
                  <th>Quick</th>
                  <th>Standard</th>
                  <th>Aggressive</th>
                </tr>
              </thead>
              <tbody id="tblToolConfigBody"></tbody>
            </table>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-top:12px; gap:8px;">
            <button class="btn-secondary" type="button" id="btnCfgReset">
              <span class="icon">↺</span><span>Reset về mặc định</span>
            </button>
            <button class="btn" type="button" id="btnCfgSave">
              <span class="icon">💾</span><span>Lưu cấu hình</span>
            </button>
          </div>
          <div class="hint">
            File cấu hình: <code>ui/static/tool_config.json</code> – được dùng bởi <code>run_all_with_grype_fix.sh</code>.
          </div>
        </div>
      </section>
    </section>

    <!-- DATA TỪ FLASK SANG JS -->
    <script>
      window.__SUMMARY__  = {{ summary|tojson }};
      window.__FINDINGS__ = {{ findings|tojson }};
      window.__TOOL_CFG__ = {{ tool_cfg_json|safe }};
      window.__TOOL_CFG_DEFAULT__ = {{ tool_cfg_default_json|safe }};
      const TOOL_CFG_API = "{{ url_for('api_tool_config') }}";
    </script>

    <!-- JS ỔN ĐỊNH: KHÔNG ĐỤNG VÀO THƯỜNG XUYÊN -->
    <script>
      const SEV_ORDER = ["CRITICAL","HIGH","MEDIUM","LOW","INFO"];
      function sevWeight(s){
        const m={CRITICAL:5,HIGH:4,MEDIUM:3,LOW:2,INFO:1};
        return m[s]||0;
      }
      function sevClass(sev){
        switch(sev){
          case "CRITICAL": return "chip-sev chip-critical";
          case "HIGH": return "chip-sev chip-high";
          case "MEDIUM": return "chip-sev chip-medium";
          case "LOW": return "chip-sev chip-low";
          default: return "chip-sev chip-info";
        }
      }
      function normSevJS(s){
        if(!s) return "INFO";
        s=String(s).trim().toUpperCase();
        if(s.includes("CRIT")) return "CRITICAL";
        if(s.includes("HIGH")) return "HIGH";
        if(s.includes("MED")) return "MEDIUM";
        if(s.includes("LOW")) return "LOW";
        if(s.includes("INFO")||s.includes("NEGLIGIBLE")||s.includes("UNKNOWN")) return "INFO";
        return s;
      }

      let sevChart = null;
      let currentToolCfg = null;

      function computeBuckets(summary, findings){
        const by = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0};
        if(summary && summary.by_severity_overall){
          for(const k of Object.keys(by)){
            by[k] = summary.by_severity_overall[k] || 0;
          }
          return by;
        }
        const arr = Array.isArray(findings) ? findings : [];
        for(const r of arr){
          const sev = normSevJS(r.severity || "");
          if(!by[sev]) by[sev] = 0;
          by[sev] += 1;
        }
        return by;
      }

      function renderDashboard(summary, findings){
        summary  = summary  || {};
        findings = Array.isArray(findings) ? findings : [];

        const buckets = computeBuckets(summary, findings);
        const total = summary.total || findings.length || 0;

        const elTotal = document.getElementById("kpiTotal");
        const tagTotal = document.getElementById("tagTotal");
        if(elTotal) elTotal.textContent = total;
        if(tagTotal) tagTotal.textContent = total + " findings";

        const crit = buckets.CRITICAL || 0;
        const high = buckets.HIGH || 0;
        const med  = buckets.MEDIUM || 0;
        const low  = buckets.LOW || 0;
        const info = buckets.INFO || 0;

        const elCrit = document.getElementById("kpiCrit");
        const elHigh = document.getElementById("kpiHigh");
        const elMed  = document.getElementById("kpiMed");
        const elLow  = document.getElementById("kpiLow");
        const elInfo = document.getElementById("kpiInfo");
        if(elCrit) elCrit.textContent = crit;
        if(elHigh) elHigh.textContent = high;
        if(elMed)  elMed.textContent  = med;
        if(elLow)  elLow.textContent  = low;
        if(elInfo) elInfo.textContent = info;

        let topSev="INFO", maxVal=0;
        for(const sev of SEV_ORDER){
          const v = buckets[sev]||0;
          if(v>maxVal && sevWeight(sev)>=sevWeight(topSev)){maxVal=v;topSev=sev;}
        }
        const elTop = document.getElementById("kpiTopSeverity");
        if(elTop) elTop.textContent = topSev;
        const elMode = document.getElementById("tagMode");
        if(elMode) elMode.textContent = summary.mode || "Offline / Aggressive";

        // Chart.js – bọc try/catch để nếu Chart lỗi vẫn không kill UI
        try{
          const labels = ["Critical","High","Medium","Low","Info"];
          const values = [crit,high,med,low,info];
          const colors = ["#ef4444","#f97316","#eab308","#22c55e","#38bdf8"];
          const canvas = document.getElementById("severityChart");
          if(canvas){
            const ctx = canvas.getContext("2d");
            if(!sevChart){
              sevChart = new Chart(ctx, {
                type: "bar",
                data: {
                  labels: labels,
                  datasets: [{
                    label: "Number of findings",
                    data: values,
                    backgroundColor: colors,
                    borderColor: colors,
                    borderWidth: 1
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: false,
                  scales: {
                    x: {
                      grid: { display: false },
                      ticks: { color: "#c7cffb" }
                    },
                    y: {
                      beginAtZero: true,
                      grid: { color: "rgba(255,255,255,0.08)" },
                      ticks: { color: "#c7cffb", precision: 0 }
                    }
                  },
                  plugins: {
                    legend: { labels: { color: "#e2e6ff" } },
                    tooltip: {
                      callbacks: {
                        label: (ctx) => {
                          const label = ctx.chart.data.labels[ctx.dataIndex] || "";
                          return " " + label + ": " + ctx.parsed.y + " findings";
                        }
                      }
                    }
                  }
                }
              });
            } else {
              sevChart.data.labels = labels;
              sevChart.data.datasets[0].data = values;
              sevChart.update();
            }
          }
        }catch(e){
          console.error("Chart error:", e);
        }

        const perTool = summary.per_tool || {};
        const tblTools=document.getElementById("tblToolsBody");
        if(tblTools){
          tblTools.innerHTML="";
          const toolNames=Object.keys(perTool).sort();
          const toolsForTag=[];
          for(const t of toolNames){
            const infoTool=perTool[t] || {};
            const row=document.createElement("tr");
            const sevMap=infoTool.by_severity || {};
            const totalTool=infoTool.total || 0;

            const cellTool=document.createElement("td");
            cellTool.innerHTML='<span class="pill-tool"><span class="pill-dot"></span><span>'+t+'</span></span>';
            row.appendChild(cellTool);
            SEV_ORDER.forEach(sev=>{
              const td=document.createElement("td");
              td.textContent=sevMap[sev]||0;
              td.className="muted";
              row.appendChild(td);
            });
            const tdTot=document.createElement("td");
            tdTot.textContent=totalTool;
            row.appendChild(tdTot);
            tblTools.appendChild(row);
            toolsForTag.push(t);
          }
          const tagTools = document.getElementById("tagTools");
          if(toolsForTag.length && tagTools){
            tagTools.textContent = toolsForTag.join(" • ");
          }
        }

        const tblTop=document.getElementById("tblTopBody");
        if(tblTop){
          tblTop.innerHTML="";
          const sorted=findings.map((r,idx)=>{
            const sev=normSevJS(r.severity||"");
            return {row:r,sev,idx};
          }).sort((a,b)=>{
            const wa=sevWeight(a.sev), wb=sevWeight(b.sev);
            if(wa!==wb) return wb-wa;
            const ta=(a.row.tool||a.row.category||"").toString();
            const tb=(b.row.tool||b.row.category||"").toString();
            return ta.localeCompare(tb);
          }).slice(0,20);

          sorted.forEach(item=>{
            const r=item.row; const sev=item.sev;
            const tr=document.createElement("tr");

            const tdSev=document.createElement("td");
            const sevSpan=document.createElement("span");
            sevSpan.className=sevClass(sev);
            sevSpan.textContent=sev;
            tdSev.appendChild(sevSpan); tr.appendChild(tdSev);

            const tdTool=document.createElement("td");
            tdTool.textContent=r.tool || r.category || "Unknown";
            tdTool.className="muted";
            tr.appendChild(tdTool);

            const tdRule=document.createElement("td");
            tdRule.textContent=r.rule||""; tdRule.className="mono";
            tr.appendChild(tdRule);

            const tdFile=document.createElement("td");
            const file=r.file||""; const line=r.line?(":"+r.line):"";
            tdFile.textContent=file?file+line:"—"; tdFile.className="mono";
            tr.appendChild(tdFile);

            const tdDesc=document.createElement("td");
            tdDesc.textContent=r.desc||""; tr.appendChild(tdDesc);

            const tdStatus=document.createElement("td");
            const status=r.status||"Open";
            const spanSt=document.createElement("span");
            spanSt.className="chip-status"; spanSt.textContent=status;
            tdStatus.appendChild(spanSt); tr.appendChild(tdStatus);

            tblTop.appendChild(tr);
          });
        }
      }

      const PROFILE_KEYS = ["quick","standard","aggr"];
      const TOOL_KEYS = ["Semgrep","Gitleaks","Bandit","TrivyVuln","TrivyMisconfig","TrivySecret","Grype"];
      const TOOL_LABELS = {
        "Semgrep": "Semgrep",
        "Gitleaks": "Gitleaks",
        "Bandit": "Bandit",
        "TrivyVuln": "Trivy Vuln",
        "TrivyMisconfig": "Trivy Misconfig",
        "TrivySecret": "Trivy Secret",
        "Grype": "Grype"
      };

      function getToolCfg(){
        if(!currentToolCfg){
          currentToolCfg = window.__TOOL_CFG__ || {profiles:{}};
        }
        if(!currentToolCfg.profiles) currentToolCfg.profiles = {};
        return currentToolCfg;
      }

      function renderToolConfig(){
        const cfg = getToolCfg();
        const profiles = cfg.profiles || {};
        const tbody = document.getElementById("tblToolConfigBody");
        if(!tbody) return;
        tbody.innerHTML = "";

        TOOL_KEYS.forEach(tool=>{
          const tr = document.createElement("tr");

          const tdName = document.createElement("td");
          tdName.innerHTML = '<span class="pill-tool"><span class="pill-dot"></span><span>'+ (TOOL_LABELS[tool] || tool) +'</span></span>';
          tr.appendChild(tdName);

          PROFILE_KEYS.forEach(p=>{
            const td = document.createElement("td");
            td.style.textAlign = "center";
            const chk = document.createElement("input");
            chk.type = "checkbox";
            chk.dataset.tool = tool;
            chk.dataset.profile = p;
            const enabled = !!(profiles[p] && profiles[p][tool]);
            chk.checked = enabled;
            td.appendChild(chk);
            tr.appendChild(td);
          });

          tbody.appendChild(tr);
        });
      }

      async function saveToolConfig(){
        const tbody = document.getElementById("tblToolConfigBody");
        if(!tbody) return;
        const profiles = {};
        PROFILE_KEYS.forEach(p=>{profiles[p] = {};});
        tbody.querySelectorAll('input[type="checkbox"][data-tool][data-profile]').forEach(chk=>{
          const t = chk.dataset.tool;
          const p = chk.dataset.profile;
          if(!profiles[p]) profiles[p] = {};
          profiles[p][t] = chk.checked;
        });
        try{
          const res = await fetch(TOOL_CFG_API, {
            method: "POST",
            headers: {"Content-Type":"application/json"},
            body: JSON.stringify({profiles: profiles})
          });
          const js = await res.json();
          if(js && js.ok){
            currentToolCfg = {profiles: profiles};
            alert("Đã lưu cấu hình tool.");
          } else {
            alert("Lưu thất bại.");
          }
        }catch(e){
          console.error(e);
          alert("Lỗi khi gọi API lưu cấu hình.");
        }
      }

      function resetToolConfig(){
        const defCfg = window.__TOOL_CFG_DEFAULT__ || window.__TOOL_CFG__ || {profiles:{}};
        currentToolCfg = JSON.parse(JSON.stringify(defCfg));
        renderToolConfig();
      }

      function setupNav(){
        const views = document.querySelectorAll(".view-section");
        const navs = document.querySelectorAll(".nav-item");
        navs.forEach(nav=>{
          nav.addEventListener("click", ()=>{
            const view = nav.getAttribute("data-view") || "scan";
            navs.forEach(n=>n.classList.remove("active"));
            nav.classList.add("active");
            views.forEach(sec=>{
              if(sec.getAttribute("data-view") === view) sec.style.display = "";
              else sec.style.display = "none";
            });
            if(view === "settings"){
              renderToolConfig();
            }
          });
        });
      }

      function readFileAsJSON(file){
        return new Promise((resolve,reject)=>{
          const reader=new FileReader();
          reader.onload=()=>{try{resolve(JSON.parse(reader.result));}catch(e){reject(e);} };
          reader.onerror=()=>reject(reader.error);
          reader.readAsText(file);
        });
      }

      window.addEventListener("DOMContentLoaded",()=>{
        let summary  = typeof window.__SUMMARY__  !== "undefined" ? window.__SUMMARY__  : {};
        let findings = typeof window.__FINDINGS__ !== "undefined" ? window.__FINDINGS__ : [];

        if(!summary || !summary.by_severity_overall){
          summary = {
            total: (Array.isArray(findings) ? findings.length : 0),
            by_severity_overall: {},
            per_tool: {}
          };
        }

        renderDashboard(summary, findings);
        setupNav();

        const btnReload = document.getElementById("btnReload");
        if(btnReload){
          btnReload.addEventListener("click", ()=>{ location.reload(); });
        }

        const btnUpload = document.getElementById("btnUploadLoad");
        if(btnUpload){
          btnUpload.addEventListener("click", async ()=>{
            const fSummary=document.getElementById("fileSummary").files[0];
            const fFindings=document.getElementById("fileFindings").files[0];
            if(!fSummary || !fFindings){
              alert("Chọn đủ cả 2 file: summary_unified.json và findings.json");
              return;
            }
            try{
              const [s,f]=await Promise.all([readFileAsJSON(fSummary),readFileAsJSON(fFindings)]);
              renderDashboard(s,f);
            }catch(e){
              console.error(e); alert("Không đọc được JSON upload.");
            }
          });
        }

        const btnSave = document.getElementById("btnCfgSave");
        const btnReset = document.getElementById("btnCfgReset");
        if(btnSave)  btnSave.addEventListener("click", saveToolConfig);
        if(btnReset) btnReset.addEventListener("click", resetToolConfig);
      });
    </script>
  </main>
</body>
</html>
"""

# ====== FLASK ROUTES ======
@app.route("/", methods=["GET"])
def index():
    summary, findings, meta = load_last_run()
    tool_cfg = load_tool_config()
    tool_cfg_default = default_tool_config()
    runs_meta = list_runs_meta()
    return render_template_string(
        TEMPLATE,
        summary=summary,
        findings=findings,
        project=meta.get("project", "No RUN"),
        last_scan=meta.get("last_scan", "—"),
        src_default=DEFAULT_SRC,
        tool_cfg_json=json.dumps(tool_cfg, ensure_ascii=False),
        tool_cfg_default_json=json.dumps(tool_cfg_default, ensure_ascii=False),
        runs_meta=runs_meta,
    )

@app.route("/run", methods=["POST"])
def run_scan():
    src = (request.form.get("src_path") or "").strip()
    profile = request.form.get("profile") or "aggr"
    mode = request.form.get("mode") or "offline"
    target_url = (request.form.get("target_url") or "").strip()

    if not src:
        # Thiếu SRC thì quay lại, không crash
        return redirect(url_for("index"))

    env = os.environ.copy()
    env["SRC"] = src
    level_map = {"quick": "fast", "standard": "std", "aggr": "aggr"}
    env["LEVEL"] = level_map.get(profile, "aggr")
    env["NO_NET"] = "1" if mode == "offline" else "0"
    if target_url:
        env["TARGET_URL"] = target_url

    try:
        subprocess.run(
            [SCAN_WRAPPER],
            env=env,
            cwd=os.path.dirname(SCAN_WRAPPER),
            check=False,
        )
    except Exception as e:
        print("[ERR] run_scan failed:", e)

    return redirect(url_for("index"))

@app.route("/api/tool-config", methods=["POST"])
def api_tool_config():
    data = request.get_json(silent=True) or {}
    profiles = data.get("profiles")
    if not isinstance(profiles, dict):
        return {"ok": False, "error": "Invalid payload"}, 400
    try:
        cfg = save_tool_config(profiles)
    except Exception as e:
        return {"ok": False, "error": str(e)}, 500
    return {"ok": True, "config": cfg}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8905, debug=True)
