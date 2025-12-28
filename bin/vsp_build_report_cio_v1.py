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
