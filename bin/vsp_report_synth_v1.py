#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import json, csv, time, os, subprocess, textwrap, shutil

def jload(p: Path):
    return json.loads(p.read_text(encoding="utf-8", errors="replace"))

def ensure_dir(p: Path):
    p.mkdir(parents=True, exist_ok=True)

def safe_get_findings(run_dir: Path):
    # prefer findings_unified.json (your standard)
    fu = run_dir / "findings_unified.json"
    if fu.is_file():
        j = jload(fu)
        if isinstance(j, dict) and "findings" in j and isinstance(j["findings"], list):
            return j["findings"], j
        # sometimes top-level list
        if isinstance(j, list):
            return j, {"findings": j}
    # fallback: other possible names
    for name in ("findings.json", "findings_unified_v1.json"):
        fp = run_dir / name
        if fp.is_file():
            j = jload(fp)
            if isinstance(j, dict) and "findings" in j and isinstance(j["findings"], list):
                return j["findings"], j
            if isinstance(j, list):
                return j, {"findings": j}
    return [], {}

def normalize_sev(s: str) -> str:
    s = (s or "").upper().strip()
    if s in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"):
        return s
    # common variants
    if s in ("ERROR","SEVERE"): return "HIGH"
    if s in ("WARN","WARNING"): return "MEDIUM"
    if s in ("NOTE","NOTICE"): return "INFO"
    return "INFO"

def write_csv(findings, out_csv: Path):
    cols = ["severity","tool","rule_id","title","file","line","message"]
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for x in findings:
            if not isinstance(x, dict): 
                continue
            w.writerow({
                "severity": normalize_sev(x.get("severity") or x.get("sev") or ""),
                "tool": x.get("tool") or x.get("engine") or "",
                "rule_id": x.get("rule_id") or x.get("check_id") or x.get("id") or "",
                "title": x.get("title") or x.get("name") or x.get("message") or "",
                "file": x.get("path") or x.get("file") or x.get("filename") or "",
                "line": x.get("line") or x.get("start_line") or "",
                "message": (x.get("message") or x.get("desc") or "")[:2000],
            })

def write_sarif(findings, out_sarif: Path):
    # Lite SARIF generator
    runs = [{
        "tool": {"driver": {"name": "VSP-Unified", "informationUri": "about:blank", "rules": []}},
        "results": []
    }]
    rule_ids = set()
    for x in findings:
        if not isinstance(x, dict): 
            continue
        rid = (x.get("rule_id") or x.get("check_id") or x.get("id") or "VSP.UNK")
        if rid not in rule_ids:
            rule_ids.add(rid)
            runs[0]["tool"]["driver"]["rules"].append({
                "id": rid,
                "name": x.get("title") or rid,
                "shortDescription": {"text": x.get("title") or rid},
            })
        msg = x.get("message") or x.get("title") or rid
        loc_path = x.get("path") or x.get("file") or ""
        line = x.get("line") or x.get("start_line") or 1
        try:
            line = int(line)
        except Exception:
            line = 1
        res = {
            "ruleId": rid,
            "level": normalize_sev(x.get("severity") or "").lower(),
            "message": {"text": msg[:4000]},
        }
        if loc_path:
            res["locations"] = [{
                "physicalLocation": {
                    "artifactLocation": {"uri": loc_path},
                    "region": {"startLine": max(1,line)}
                }
            }]
        runs[0]["results"].append(res)

    sarif = {
        "version": "2.1.0",
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "runs": runs
    }
    out_sarif.write_text(json.dumps(sarif, ensure_ascii=False), encoding="utf-8")

def write_html(report_title: str, findings, out_html: Path):
    # Minimal commercial dark report
    counts = {k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}
    for x in findings:
        if isinstance(x, dict):
            counts[normalize_sev(x.get("severity") or x.get("sev") or "")] += 1

    rows = []
    for x in findings[:5000]:
        if not isinstance(x, dict): 
            continue
        rows.append((
            normalize_sev(x.get("severity") or x.get("sev") or ""),
            x.get("tool") or "",
            x.get("rule_id") or x.get("check_id") or "",
            (x.get("title") or x.get("message") or "")[:220],
            x.get("path") or x.get("file") or "",
            str(x.get("line") or x.get("start_line") or ""),
        ))

    html = f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>{report_title}</title>
<style>
body{{font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;background:#070e1a;color:#e6eefc;margin:0}}
.container{{max-width:1200px;margin:0 auto;padding:24px}}
h1{{margin:0 0 8px 0;font-size:22px}}
.kpis{{display:flex;gap:12px;flex-wrap:wrap;margin:14px 0 18px 0}}
.kpi{{background:#0c162a;border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:10px 12px;min-width:120px}}
.kpi .n{{font-size:18px;font-weight:700}}
small{{opacity:.8}}
table{{width:100%;border-collapse:collapse;background:#0c162a;border:1px solid rgba(255,255,255,.08);border-radius:14px;overflow:hidden}}
th,td{{padding:10px 10px;border-bottom:1px solid rgba(255,255,255,.06);font-size:13px;vertical-align:top}}
th{{text-align:left;opacity:.9;font-weight:600}}
tr:hover td{{background:rgba(255,255,255,.03)}}
.badge{{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.12);font-size:12px}}
</style>
</head><body>
<div class="container">
<h1>{report_title}</h1>
<small>Generated by VSP Report Synth • {time.strftime("%Y-%m-%d %H:%M:%S")}</small>
<div class="kpis">
{''.join([f'<div class="kpi"><div class="n">{counts[k]}</div><div><span class="badge">{k}</span></div></div>' for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]])}
</div>
<table>
<thead><tr><th>Severity</th><th>Tool</th><th>Rule</th><th>Title</th><th>File</th><th>Line</th></tr></thead>
<tbody>
{''.join([f'<tr><td>{a}</td><td>{b}</td><td>{c}</td><td>{d}</td><td>{e}</td><td>{f}</td></tr>' for (a,b,c,d,e,f) in rows])}
</tbody></table>
</div></body></html>
"""
    out_html.write_text(html, encoding="utf-8")

def try_pdf(html_path: Path, pdf_path: Path):
    # Prefer weasyprint; else wkhtmltopdf; else skip
    # Return (ok, method)
    try:
        import weasyprint  # type: ignore
        weasyprint.HTML(filename=str(html_path)).write_pdf(str(pdf_path))
        return True, "weasyprint"
    except Exception:
        pass
    wk = shutil.which("wkhtmltopdf")
    if wk:
        try:
            subprocess.check_call([wk, str(html_path), str(pdf_path)])
            return True, "wkhtmltopdf"
        except Exception:
            pass
    return False, "none"

def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--title", default="VSP Findings Report")
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    if not run_dir.is_dir():
        raise SystemExit(f"[ERR] run_dir not found: {run_dir}")

    reports = run_dir / "reports"
    ensure_dir(reports)

    findings, _meta = safe_get_findings(run_dir)

    # outputs
    out_csv = reports / "findings_unified.csv"
    out_sarif = reports / "findings_unified.sarif"
    out_html = reports / "findings_unified.html"
    out_pdf  = reports / "findings_unified.pdf"

    created = []
    degraded = []

    if not out_csv.is_file():
        write_csv(findings, out_csv); created.append(str(out_csv))
    if not out_sarif.is_file():
        write_sarif(findings, out_sarif); created.append(str(out_sarif))
    if not out_html.is_file():
        write_html(args.title, findings, out_html); created.append(str(out_html))
    if not out_pdf.is_file():
        ok, method = try_pdf(out_html, out_pdf)
        if ok:
            created.append(str(out_pdf))
        else:
            degraded.append("pdf:no_renderer")

    # manifest note
    note = {
        "ok": True,
        "run_dir": str(run_dir),
        "created": created,
        "degraded": degraded,
        "ts": int(time.time()),
    }
    (reports / "report_synth_v1.json").write_text(json.dumps(note, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(note, ensure_ascii=False))
if __name__ == "__main__":
    main()
