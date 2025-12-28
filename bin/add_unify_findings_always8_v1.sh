#!/usr/bin/env bash
set -euo pipefail

OUTPY="/home/test/Data/SECURITY_BUNDLE/bin/vsp_unify_findings_always8_v1.py"
mkdir -p "$(dirname "$OUTPY")"

cat > "$OUTPY" <<'PY'
#!/usr/bin/env python3
import json, os, re, sys, glob, hashlib
from pathlib import Path

CANON_TOOLS = ["SEMGREP","GITLEAKS","TRIVY","CODEQL","KICS","GRYPE","SYFT","BANDIT"]
SEV6 = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]

def jload(p):
    try:
        return json.load(open(p,"r",encoding="utf-8",errors="ignore"))
    except Exception:
        return None

def norm_sev(x):
    s = (str(x or "")).strip().upper()
    m = {
        "CRITICAL":"CRITICAL","ERROR":"HIGH","HIGH":"HIGH","WARNING":"MEDIUM","MEDIUM":"MEDIUM",
        "LOW":"LOW","INFO":"INFO","NOTE":"INFO","NONE":"TRACE","UNKNOWN":"TRACE","PASS":"TRACE",
        "RED":"HIGH","AMBER":"MEDIUM","GREEN":"INFO","FAIL":"HIGH","OK":"INFO","NOT_RUN":"TRACE"
    }
    if s in m: return m[s]
    # semgrep uses "WARNING"/"ERROR"
    if "CRIT" in s: return "CRITICAL"
    if "HIGH" in s: return "HIGH"
    if "MED" in s: return "MEDIUM"
    if "LOW" in s: return "LOW"
    if "INFO" in s: return "INFO"
    return "TRACE"

def pick_cwe(text):
    if not text: return None
    m = re.search(r"\bCWE[-\s]?(\d+)\b", str(text), flags=re.I)
    if m: return f"CWE-{m.group(1)}"
    return None

def fp(*parts):
    h = hashlib.sha1()
    for p in parts:
        if p is None: p=""
        h.update(str(p).encode("utf-8", errors="ignore"))
        h.update(b"\x1f")
    return h.hexdigest()

def add(items, tool, severity, title, file=None, line=None, rule=None, cwe=None, raw=None):
    sev = norm_sev(severity)
    it = {
        "tool": tool,
        "severity": sev,
        "title": title or f"{tool} finding",
        "cwe": cwe,
        "file": file,
        "line": line,
        "rule": rule,
        "fingerprint": fp(tool, sev, title, file, line, rule, cwe),
        "raw": raw if isinstance(raw,(dict,list,str,int,float,bool)) else None
    }
    items.append(it)

def find_first(base, patterns):
    for pat in patterns:
        hits = glob.glob(str(base / pat))
        if hits:
            hits.sort(key=lambda x: len(x))
            return Path(hits[0])
    return None

def parse_gitleaks(run_dir, items):
    # typical: gitleaks/gitleaks.json or gitleaks/gitleaks_findings.json
    p = find_first(run_dir, ["gitleaks/*.json","**/gitleaks*.json"])
    if not p: return
    data = jload(p)
    if isinstance(data, dict) and "leaks" in data: data = data.get("leaks")
    if not isinstance(data, list): return
    for r in data:
        title = r.get("Description") or r.get("description") or r.get("RuleID") or "Secret detected"
        f = r.get("File") or r.get("file") or r.get("path")
        ln = r.get("StartLine") or r.get("line") or r.get("Line")
        rule = r.get("RuleID") or r.get("rule") or "gitleaks"
        add(items,"GITLEAKS","HIGH",title,f,ln,rule,pick_cwe(title),r)

def parse_semgrep(run_dir, items):
    # semgrep json: semgrep/semgrep.json or semgrep/results.json
    p = find_first(run_dir, ["semgrep/*.json","**/semgrep*.json"])
    if not p: return
    data = jload(p)
    if not isinstance(data, dict): return
    results = data.get("results") or data.get("runs")  # handle SARIF-ish
    if isinstance(results, list) and results and isinstance(results[0], dict) and "tool" in results[0]:
        # sarif
        for run in results:
            for res in (run.get("results") or []):
                msg = ((res.get("message") or {}).get("text")) if isinstance(res.get("message"), dict) else res.get("message")
                title = msg or res.get("ruleId") or "semgrep finding"
                sev = (res.get("properties") or {}).get("severity") or (res.get("level") or "MEDIUM")
                loc = (res.get("locations") or [{}])[0].get("physicalLocation", {})
                art = (loc.get("artifactLocation") or {}).get("uri")
                reg = (loc.get("region") or {})
                line = reg.get("startLine")
                add(items,"SEMGREP",sev,title,art,line,res.get("ruleId"),pick_cwe(title),res)
        return
    if not isinstance(results, list): return
    for r in results:
        extra = r.get("extra") or {}
        title = extra.get("message") or r.get("check_id") or "semgrep finding"
        sev = extra.get("severity") or "MEDIUM"
        path = (r.get("path") or r.get("file")) if isinstance(r, dict) else None
        line = None
        try:
            line = (r.get("start", {}) or {}).get("line")
        except Exception:
            pass
        rule = r.get("check_id") or extra.get("metadata",{}).get("id")
        cwe = pick_cwe(extra.get("metadata",{}).get("cwe")) or pick_cwe(title)
        add(items,"SEMGREP",sev,title,path,line,rule,cwe,r)

def parse_trivy(run_dir, items):
    # trivy json: trivy/trivy.json or trivy_fs.json
    p = find_first(run_dir, ["trivy/*.json","**/trivy*.json"])
    if not p: return
    data = jload(p)
    if not isinstance(data, (dict,list)): return
    # Trivy format: {"Results":[{"Vulnerabilities":[...]}]}
    results = data.get("Results") if isinstance(data, dict) else data
    if not isinstance(results, list): return
    for r in results:
        for v in (r.get("Vulnerabilities") or []):
            title = v.get("Title") or v.get("VulnerabilityID") or "trivy vuln"
            sev = v.get("Severity") or "MEDIUM"
            pkg = v.get("PkgName")
            f = r.get("Target") or v.get("PkgPath") or v.get("InstalledPath")
            cwe = None
            if isinstance(v.get("CweIDs"), list) and v["CweIDs"]:
                cwe = f"CWE-{str(v['CweIDs'][0]).replace('CWE-','')}"
            add(items,"TRIVY",sev,title,f,None,pkg,cwe,v)

def parse_codeql(run_dir, items):
    # codeql sarif: codeql/*.sarif
    p = find_first(run_dir, ["codeql/*.sarif","**/*codeql*.sarif","**/*.sarif"])
    if not p: return
    data = jload(p)
    if not isinstance(data, dict): return
    for run in (data.get("runs") or []):
        for res in (run.get("results") or []):
            rule = res.get("ruleId")
            msg = res.get("message")
            title = (msg.get("text") if isinstance(msg, dict) else msg) or rule or "codeql finding"
            lvl = res.get("level") or (res.get("properties") or {}).get("severity") or "MEDIUM"
            loc = (res.get("locations") or [{}])[0].get("physicalLocation", {})
            art = (loc.get("artifactLocation") or {}).get("uri")
            reg = (loc.get("region") or {})
            line = reg.get("startLine")
            add(items,"CODEQL",lvl,title,art,line,rule,pick_cwe(title),res)

def parse_kics(run_dir, items):
    # kics json: kics/*.json
    p = find_first(run_dir, ["kics/*.json","**/kics*.json"])
    if not p: return
    data = jload(p)
    if not isinstance(data, dict): return
    queries = data.get("queries") or data.get("Queries") or []
    if not isinstance(queries, list): return
    for q in queries:
        qname = q.get("query_name") or q.get("QueryName") or q.get("queryName") or "KICS issue"
        sev = q.get("severity") or q.get("Severity") or "MEDIUM"
        for fnd in (q.get("files") or q.get("Files") or []):
            fpath = fnd.get("file_name") or fnd.get("fileName") or fnd.get("file") or fnd.get("filename")
            line = fnd.get("line") or fnd.get("Line")
            add(items,"KICS",sev,qname,fpath,line,q.get("query_id") or q.get("QueryID"),pick_cwe(qname),fnd)

def parse_grype(run_dir, items):
    # grype json: grype/*.json
    p = find_first(run_dir, ["grype/*.json","**/grype*.json"])
    if not p: return
    data = jload(p)
    if not isinstance(data, dict): return
    matches = data.get("matches") or []
    for m in matches:
        vuln = (m.get("vulnerability") or {})
        art = (m.get("artifact") or {})
        title = vuln.get("id") or "grype vuln"
        sev = vuln.get("severity") or "MEDIUM"
        pkg = art.get("name")
        add(items,"GRYPE",sev,title,art.get("name"),None,pkg,pick_cwe(title),m)

def parse_syft(run_dir, items):
    # syft is inventory; for commercial, expose as INFO summary finding to show lane exists
    p = find_first(run_dir, ["syft/*.json","**/syft*.json"])
    if not p: return
    data = jload(p)
    if not data: return
    # count packages
    pkgs = data.get("artifacts") if isinstance(data, dict) else None
    n = len(pkgs) if isinstance(pkgs, list) else 0
    add(items,"SYFT","INFO",f"SBOM generated ({n} packages)",str(p),None,"syft",None,{"packages_n": n})

def parse_bandit(run_dir, items):
    p = find_first(run_dir, ["bandit/*.json","**/bandit*.json"])
    if not p: return
    data = jload(p)
    if not isinstance(data, dict): return
    res = data.get("results") or []
    for r in res:
        title = r.get("issue_text") or r.get("test_name") or "bandit finding"
        sev = r.get("issue_severity") or "LOW"
        f = r.get("filename")
        line = r.get("line_number")
        rule = r.get("test_id") or r.get("test_name")
        add(items,"BANDIT",sev,title,f,line,rule,pick_cwe(title),r)

def main():
    if len(sys.argv) < 2:
        print("Usage: vsp_unify_findings_always8_v1.py <RUN_DIR>")
        return 2
    run_dir = Path(sys.argv[1]).resolve()
    if not run_dir.exists():
        print("[ERR] run dir not found:", run_dir)
        return 2

    items = []
    parse_gitleaks(run_dir, items)
    parse_semgrep(run_dir, items)
    parse_trivy(run_dir, items)
    parse_codeql(run_dir, items)
    parse_kics(run_dir, items)
    parse_grype(run_dir, items)
    parse_syft(run_dir, items)
    parse_bandit(run_dir, items)

    # stable sort: tool -> severity rank -> title
    sev_rank = {k:i for i,k in enumerate(SEV6)}
    items.sort(key=lambda x: (x.get("tool",""), sev_rank.get(x.get("severity","TRACE"), 99), x.get("title","")))

    out = {
        "schema": "vsp.findings_unified.v1",
        "run_dir": str(run_dir),
        "total": len(items),
        "items": items
    }

    # write both locations
    out1 = run_dir / "findings_unified.json"
    out2 = run_dir / "reports" / "findings_unified.json"
    out2.parent.mkdir(parents=True, exist_ok=True)
    for op in [out1, out2]:
        op.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print("[OK] wrote", out1)
    print("[OK] wrote", out2)
    print("[OK] total", len(items))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$OUTPY"
echo "[OK] wrote $OUTPY"
