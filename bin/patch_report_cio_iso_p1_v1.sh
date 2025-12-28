#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

APP="vsp_demo_app.py"
TPL="report_templates/vsp_report_cio_v1.html"
MAP="report_templates/iso27001_map_v1.json"
REN="bin/vsp_build_report_cio_v1.py"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

mkdir -p report_templates bin

cp -f "$APP" "$APP.bak_report_cio_${TS}" && echo "[BACKUP] $APP.bak_report_cio_${TS}"

# 1) ISO27001 mapping (best-effort starter map; refine later)
cat > "$MAP" <<'JSON'
{
  "version": "iso27001_map_v1",
  "notes": "Best-effort mapping for commercial CIO report. Refine per org policy and ISO edition.",
  "cwe_to_controls": {
    "CWE-79":  ["A.14.2.1", "A.14.2.5", "A.12.6.1"],
    "CWE-89":  ["A.14.2.1", "A.14.2.5", "A.12.6.1"],
    "CWE-22":  ["A.14.2.1", "A.14.2.5", "A.12.6.1"],
    "CWE-287": ["A.9.2.1", "A.9.4.2", "A.14.2.1"],
    "CWE-306": ["A.9.1.1", "A.9.4.2"],
    "CWE-200": ["A.8.2.3", "A.13.2.1", "A.18.1.4"],
    "CWE-311": ["A.10.1.1", "A.10.1.2", "A.13.2.1"],
    "CWE-798": ["A.9.2.4", "A.10.1.2", "A.12.6.1"],
    "CWE-321": ["A.10.1.2", "A.12.6.1"],
    "CWE-327": ["A.10.1.1", "A.10.1.2"],
    "CWE-352": ["A.14.2.1", "A.14.2.5"],
    "CWE-434": ["A.14.2.1", "A.12.6.1"],
    "CWE-94":  ["A.14.2.1", "A.12.6.1"],
    "CWE-502": ["A.14.2.1", "A.12.6.1"]
  },
  "tool_to_controls": {
    "gitleaks": ["A.9.2.4", "A.10.1.2", "A.12.6.1"],
    "grype":    ["A.12.6.1", "A.14.2.1"],
    "syft":     ["A.12.6.1"],
    "kics":     ["A.12.6.1", "A.14.2.1"],
    "codeql":   ["A.14.2.1", "A.14.2.5"],
    "semgrep":  ["A.14.2.1", "A.14.2.5"],
    "bandit":   ["A.14.2.1", "A.14.2.5"],
    "trivy":    ["A.12.6.1"]
  }
}
JSON
echo "[OK] wrote $MAP"

# 2) HTML template (dark executive report)
cat > "$TPL" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>VSP CIO Security Report - {{ rid }}</title>
  <style>
    :root{
      --bg:#020617; --panel:#0b1220; --card:#0f172a; --muted:#94a3b8; --text:#e2e8f0;
      --bd:rgba(148,163,184,.18); --bd2:rgba(148,163,184,.12);
    }
    *{box-sizing:border-box}
    body{margin:0;background:linear-gradient(180deg,var(--bg),#071024);color:var(--text);font:13px/1.55 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial}
    .wrap{max-width:1180px;margin:0 auto;padding:26px 18px 80px}
    .top{display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;justify-content:space-between}
    h1{margin:0;font-size:22px;letter-spacing:.2px}
    .sub{color:var(--muted);font-size:12px;margin-top:6px}
    .pill{display:inline-flex;gap:8px;align-items:center;padding:6px 10px;border-radius:999px;border:1px solid var(--bd);background:rgba(15,23,42,.55);color:var(--text);font-size:12px}
    .grid{display:grid;grid-template-columns:repeat(12,1fr);gap:12px;margin-top:14px}
    .card{grid-column:span 3;border:1px solid var(--bd);background:rgba(15,23,42,.45);border-radius:16px;padding:12px}
    .k{color:var(--muted);font-size:12px}
    .v{font-size:20px;font-weight:800;margin-top:4px}
    .row{display:grid;grid-template-columns:repeat(12,1fr);gap:12px;margin-top:12px}
    .panel{grid-column:span 12;border:1px solid var(--bd);background:rgba(2,6,23,.35);border-radius:18px;padding:14px}
    .panel h2{margin:0 0 10px 0;font-size:14px;letter-spacing:.2px}
    table{width:100%;border-collapse:separate;border-spacing:0 8px}
    td,th{padding:9px 10px;border:1px solid var(--bd2);background:rgba(2,6,23,.35);text-align:left;vertical-align:top}
    tr td:first-child,tr th:first-child{border-radius:12px 0 0 12px}
    tr td:last-child,tr th:last-child{border-radius:0 12px 12px 0}
    .muted{color:var(--muted)}
    code{background:rgba(2,6,23,.7);border:1px solid var(--bd2);padding:2px 6px;border-radius:8px}
    .two{grid-column:span 6}
    .three{grid-column:span 4}
    .small{font-size:12px}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="top">
      <div>
        <h1>VSP CIO Security Report</h1>
        <div class="sub">
          RID: <code>{{ rid }}</code> • Source: <code>{{ source }}</code> • Generated (UTC): <code>{{ now_utc }}</code>
        </div>
      </div>
      <div style="display:flex;gap:10px;flex-wrap:wrap">
        <span class="pill">Overall: <b>{{ overall }}</b></span>
        <span class="pill">Security Score: <b>{{ score }}</b></span>
        <span class="pill">Degraded tools: <b>{{ degraded_n }}</b></span>
        <span class="pill">Overrides applied: <b>{{ overrides.applied_n }}</b></span>
      </div>
    </div>

    <div class="grid">
      <div class="card"><div class="k">Total findings (raw)</div><div class="v">{{ totals.raw }}</div></div>
      <div class="card"><div class="k">Total findings (effective)</div><div class="v">{{ totals.effective }}</div></div>
      <div class="card"><div class="k">Critical + High</div><div class="v">{{ totals.crit_high }}</div></div>
      <div class="card"><div class="k">Top risky tool</div><div class="v" style="font-size:16px">{{ top.tool }}</div><div class="muted small">{{ top.tool_n }} findings</div></div>
    </div>

    <div class="row">
      <div class="panel two">
        <h2>Executive Summary</h2>
        <div class="muted small">
          This report summarizes security posture for the selected run. “Effective” findings reflect Rule Overrides (suppress/severity changes).
          Degraded tools may reduce confidence for certain categories.
        </div>
        <div style="margin-top:10px" class="small">
          <b>Top CWE:</b> {{ top.cwe }} ({{ top.cwe_n }}) •
          <b>Overrides:</b> matched={{ overrides.matched_n }}, suppressed={{ overrides.suppressed_n }}, changed={{ overrides.changed_severity_n }}, expired={{ overrides.expired_match_n }}.
        </div>
      </div>

      <div class="panel two">
        <h2>Breakdown by Severity</h2>
        <table>
          <tr><th>Severity</th><th>Count</th></tr>
          {% for k,v in by_sev %}
          <tr><td><b>{{ k }}</b></td><td>{{ v }}</td></tr>
          {% endfor %}
        </table>
      </div>
    </div>

    <div class="row">
      <div class="panel three">
        <h2>Top Tools</h2>
        <table>
          <tr><th>Tool</th><th>Count</th></tr>
          {% for k,v in by_tool %}
          <tr><td><b>{{ k }}</b></td><td>{{ v }}</td></tr>
          {% endfor %}
        </table>
      </div>

      <div class="panel three">
        <h2>Top CWE</h2>
        <table>
          <tr><th>CWE</th><th>Count</th></tr>
          {% for k,v in by_cwe %}
          <tr><td><b>{{ k }}</b></td><td>{{ v }}</td></tr>
          {% endfor %}
        </table>
      </div>

      <div class="panel three">
        <h2>ISO 27001 Coverage</h2>
        <div class="muted small">Controls inferred from CWE/tool mapping (best-effort).</div>
        <table>
          <tr><th>Control</th><th>Evidence</th></tr>
          {% for it in iso_controls %}
          <tr><td><b>{{ it.control }}</b></td><td class="small">{{ it.evidence }}</td></tr>
          {% endfor %}
        </table>
      </div>
    </div>

    <div class="row">
      <div class="panel">
        <h2>Top Findings (sample)</h2>
        <table>
          <tr>
            <th>Severity</th><th>Tool</th><th>Title</th><th>File</th><th>Line</th><th>CWE</th>
          </tr>
          {% for f in top_findings %}
          <tr>
            <td><b>{{ f.severity }}</b></td>
            <td>{{ f.tool }}</td>
            <td class="small">{{ f.title }}</td>
            <td class="small">{{ f.file }}</td>
            <td>{{ f.line }}</td>
            <td>{{ f.cwe }}</td>
          </tr>
          {% endfor %}
        </table>
      </div>
    </div>

    <div class="row">
      <div class="panel">
        <h2>Artifacts</h2>
        <div class="small muted">Open raw artifacts via API (logs, JSON, SARIF).</div>
        <div style="margin-top:10px;display:flex;gap:10px;flex-wrap:wrap">
          {% for a in artifacts %}
            {% if a.url %}
              <a class="pill" href="{{ a.url }}" target="_blank" rel="noopener">{{ a.name }}</a>
            {% else %}
              <span class="pill muted">{{ a.name }}</span>
            {% endif %}
          {% endfor %}
        </div>
      </div>
    </div>

    <div class="sub" style="margin-top:16px">
      Generated by VSP Report CIO v1 • ISO mapping is best-effort and must be verified for compliance reporting.
    </div>
  </div>
</body>
</html>
HTML
echo "[OK] wrote $TPL"

# 3) Renderer
cat > "$REN" <<'PY'
#!/usr/bin/env python3
import json, os, datetime
from collections import Counter

SEV_ORDER = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]

def _load_json(p):
    try:
        with open(p,"r",encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def _pick_items(doc):
    if not isinstance(doc, dict): return []
    for k in ("items","findings","results"):
        v = doc.get(k)
        if isinstance(v, list): return v
    # sometimes nested
    if isinstance(doc.get("data"), dict):
        for k in ("items","findings","results"):
            v = doc["data"].get(k)
            if isinstance(v, list): return v
    return []

def _sev_rank(s):
    try: return SEV_ORDER.index(str(s).upper())
    except Exception: return 999

def _get_cwe(it):
    c = it.get("cwe")
    if isinstance(c, list) and c: return str(c[0])
    if isinstance(c, str) and c: return c
    c = it.get("cwe_id") or it.get("cweId")
    return str(c) if c else "—"

def _get_line(it):
    for k in ("line","start_line","startLine"):
        v = it.get(k)
        if isinstance(v,int): return v
        if isinstance(v,str) and v.isdigit(): return int(v)
    return ""

def _get_file(it):
    for k in ("file","path","filename"):
        v = it.get(k)
        if isinstance(v,str) and v: return v
    return "—"

def build(run_dir:str, ui_root:str):
    now_utc = datetime.datetime.utcnow().isoformat()+"Z"

    fu = os.path.join(run_dir, "findings_unified.json")
    fe = os.path.join(run_dir, "findings_effective.json")

    source = "effective" if os.path.isfile(fe) else "raw"
    doc = _load_json(fe if source=="effective" else fu) or {}
    items = _pick_items(doc)

    raw_total = len(_pick_items(_load_json(fu) or {})) if os.path.isfile(fu) else len(items)
    eff_total = len(items)

    by_sev = Counter([str(it.get("severity","")).upper() or "INFO" for it in items])
    by_tool = Counter([str(it.get("tool","unknown")) for it in items])
    by_cwe = Counter([_get_cwe(it) for it in items if _get_cwe(it) not in ("—","None","null")])

    # normalize severity order list
    sev_rows = []
    for s in SEV_ORDER:
        if by_sev.get(s,0):
            sev_rows.append((s, by_sev[s]))
    # include unknown at end
    for k,v in by_sev.items():
        if k not in SEV_ORDER:
            sev_rows.append((k,v))

    tool_rows = sorted(by_tool.items(), key=lambda kv: (-kv[1], kv[0]))[:12]
    cwe_rows  = sorted(by_cwe.items(),  key=lambda kv: (-kv[1], kv[0]))[:12]

    top_tool, top_tool_n = (tool_rows[0][0], tool_rows[0][1]) if tool_rows else ("—",0)
    top_cwe, top_cwe_n   = (cwe_rows[0][0], cwe_rows[0][1]) if cwe_rows else ("—",0)

    # overrides delta (if effective format carries delta)
    overrides = {"matched_n":0,"applied_n":0,"suppressed_n":0,"changed_severity_n":0,"expired_match_n":0}
    if isinstance(doc, dict):
        d = doc.get("delta") or {}
        if isinstance(d, dict):
            overrides["matched_n"] = int(d.get("matched_n") or 0)
            overrides["applied_n"] = int(d.get("applied_n") or 0)
            overrides["suppressed_n"] = int(d.get("suppressed_n") or 0)
            overrides["changed_severity_n"] = int(d.get("changed_severity_n") or 0)
            overrides["expired_match_n"] = int(d.get("expired_match_n") or 0)

    # degraded heuristic: if .json.err exists or missing some known artifacts
    degraded_n = 0
    for rel in ("trivy/trivy.json.err",):
        if os.path.exists(os.path.join(run_dir, rel)):
            degraded_n += 1

    # security score (simple baseline)
    crit_high = by_sev.get("CRITICAL",0) + by_sev.get("HIGH",0)
    score = max(0, 100 - (by_sev.get("CRITICAL",0)*12 + by_sev.get("HIGH",0)*6 + by_sev.get("MEDIUM",0)*2))
    overall = "GREEN"
    if by_sev.get("CRITICAL",0) > 0 or by_sev.get("HIGH",0) >= 5: overall = "RED"
    elif by_sev.get("HIGH",0) > 0 or by_sev.get("MEDIUM",0) >= 20: overall = "AMBER"

    # ISO mapping
    iso_map = _load_json(os.path.join(ui_root, "report_templates/iso27001_map_v1.json")) or {}
    cwe2 = (iso_map.get("cwe_to_controls") or {})
    tool2 = (iso_map.get("tool_to_controls") or {})

    controls = Counter()
    evidence = {}
    # by top CWE
    for cwe, n in cwe_rows[:8]:
        for ctl in cwe2.get(cwe, []):
            controls[ctl] += n
            evidence.setdefault(ctl, []).append(f"{cwe}×{n}")
    # by top tool
    for tool, n in tool_rows[:8]:
        for ctl in tool2.get(tool, []):
            controls[ctl] += n
            evidence.setdefault(ctl, []).append(f"{tool}×{n}")

    iso_controls = []
    for ctl, n in controls.most_common(12):
        iso_controls.append({"control": ctl, "evidence": ", ".join(evidence.get(ctl, [])[:6])})

    # top findings sample
    def key(it):
        return (_sev_rank(it.get("severity","INFO")), str(it.get("tool","")), str(it.get("title","")))
    top = sorted(items, key=key)[:25]
    top_findings = []
    for it in top:
        top_findings.append({
            "severity": str(it.get("severity","INFO")).upper(),
            "tool": str(it.get("tool","unknown")),
            "title": str(it.get("title",""))[:220],
            "file": _get_file(it),
            "line": _get_line(it),
            "cwe": _get_cwe(it),
        })

    # artifacts via API URLs (use whitelisted names)
    artifacts = []
    whitelist = [
      "kics/kics.log","kics/kics_summary.json","trivy/trivy.json.err",
      "gitleaks/gitleaks.json","bandit/bandit.json",
      "findings_effective.json","findings_unified.json"
    ]
    rid = os.path.basename(run_dir.rstrip("/"))
    for name in whitelist:
        ap = os.path.join(run_dir, name)
        url = f"/api/vsp/run_artifact_raw_v1/{rid}?rel={name}" if os.path.isfile(ap) else None
        artifacts.append({"name": name, "url": url})

    out = {
      "rid": rid,
      "run_dir": run_dir,
      "source": source,
      "now_utc": now_utc,
      "overall": overall,
      "score": score,
      "degraded_n": degraded_n,
      "totals": {"raw": raw_total, "effective": eff_total, "crit_high": crit_high},
      "top": {"tool": top_tool, "tool_n": top_tool_n, "cwe": top_cwe, "cwe_n": top_cwe_n},
      "by_sev": sev_rows,
      "by_tool": tool_rows,
      "by_cwe": cwe_rows,
      "iso_controls": iso_controls,
      "overrides": overrides,
      "top_findings": top_findings,
      "artifacts": artifacts
    }
    return out

def main():
    import sys
    if len(sys.argv) < 3:
        print("usage: vsp_build_report_cio_v1.py <run_dir> <ui_root>")
        return 2
    run_dir = sys.argv[1]
    ui_root = sys.argv[2]
    doc = build(run_dir, ui_root)
    print(json.dumps(doc, ensure_ascii=False, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
PY
chmod +x "$REN"
echo "[OK] wrote $REN"

# 4) Patch backend endpoint (HTML only; doesn't disturb existing export)
python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="### VSP_REPORT_CIO_V1 ###"
if MARK in s:
    print("[SKIP] report cio already present")
    raise SystemExit(0)

# insert before __main__ if present
m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
inject_at = m.start() if m else len(s)

block = r'''
### VSP_REPORT_CIO_V1 ###
import os
from flask import Response, jsonify, request

def _vsp_run_dir_report_cio_v1(rid: str):
    # Try reuse existing resolver if already defined by other patches
    for nm in ("_vsp_resolve_run_dir_by_rid", "_vsp_resolve_run_dir_by_rid_v1", "_vsp_resolve_run_dir_by_rid_v2"):
        fn = globals().get(nm)
        if callable(fn):
            rd = fn(rid)
            if rd: return rd
    # Fallback minimal glob resolver
    import glob
    pats = [
      f"/home/test/Data/*/out_ci/{rid}",
      f"/home/test/Data/*/out/{rid}",
      f"/home/test/Data/SECURITY-10-10-v4/out_ci/{rid}",
      f"/home/test/Data/SECURITY_BUNDLE/out_ci/{rid}",
    ]
    for pat in pats:
        for d in glob.glob(pat):
            if os.path.isdir(d):
                return d
    return None

@app.get("/api/vsp/run_report_cio_v1/<rid>")
def api_vsp_run_report_cio_v1(rid):
    rd = _vsp_run_dir_report_cio_v1(rid)
    if not rd:
        return jsonify({"ok": False, "rid": rid, "error": "run_dir_not_found"}), 200

    ui_root = os.path.abspath(os.path.dirname(__file__))
    tpl_path = os.path.join(ui_root, "report_templates", "vsp_report_cio_v1.html")
    if not os.path.isfile(tpl_path):
        return jsonify({"ok": False, "rid": rid, "error": "template_missing", "template": tpl_path}), 500

    # build context
    import json, subprocess
    try:
        out = subprocess.check_output(
            [os.path.join(ui_root, "bin", "vsp_build_report_cio_v1.py"), rd, ui_root],
            stderr=subprocess.STDOUT,
            text=True
        )
        ctx = json.loads(out)
    except Exception as e:
        return jsonify({"ok": False, "rid": rid, "error": "renderer_failed", "detail": str(e)}), 500

    # render via Jinja2 environment already in Flask
    from flask import render_template_string
    tpl = open(tpl_path, "r", encoding="utf-8").read()
    html = render_template_string(tpl, **ctx)

    # optional write into run_dir for archiving
    try:
        rep_dir = os.path.join(rd, "reports")
        os.makedirs(rep_dir, exist_ok=True)
        out_html = os.path.join(rep_dir, "vsp_run_report_cio_v1.html")
        with open(out_html, "w", encoding="utf-8") as f:
            f.write(html)
    except Exception:
        pass

    return Response(html, status=200, content_type="text/html; charset=utf-8")
'''
s2 = s[:inject_at] + "\n" + block + "\n" + s[inject_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected report cio endpoint")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patch_report_cio_iso_p1_v1"
