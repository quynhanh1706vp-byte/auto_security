#!/usr/bin/env python3
import json, os, sys, urllib.request, urllib.error, re
from pathlib import Path
from datetime import datetime

BASE = os.environ.get("BASE", "http://127.0.0.1:8910").rstrip("/")

def get(path: str, timeout=12):
    url = BASE + path
    req = urllib.request.Request(url, headers={"User-Agent":"vsp-gate/4"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode("utf-8", "ignore")
            code = getattr(r, "status", 200)
            return code, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "ignore") if e.fp else ""
        return e.code, body
    except Exception as e:
        return 0, str(e)

def load_json(body: str):
    # Python json loads accepts NaN/Infinity by default
    return json.loads(body)

def must(desc, cond, details=""):
    if not cond:
        print(f"[FAIL] {desc}")
        if details:
            print("  " + details.replace("\n"," ")[:800])
        sys.exit(2)
    print(f"[OK] {desc}")

def warn(desc, details=""):
    print(f"[WARN] {desc}")
    if details:
        print("  " + details.replace("\n"," ")[:800])

def main():
    print(f"[GATE] VSP Commercial Gate v4 @ {datetime.now().isoformat()} BASE={BASE}")

    # 1) ops
    c, b = get("/healthz", timeout=8)
    must("healthz HTTP 200", c == 200, f"HTTP={c} body={b[:220]}")
    j = load_json(b)
    must("healthz ok==true", j.get("ok") is True, b[:220])

    c, b = get("/api/vsp/version", timeout=8)
    must("version HTTP 200", c == 200, f"HTTP={c} body={b[:220]}")
    j = load_json(b)
    must("version ok==true", j.get("ok") is True, b[:220])
    must("version has git_hash field", isinstance(j.get("info",{}).get("git_hash",""), str), b[:220])

    # 2) dashboard contract
    c, b = get("/api/vsp/dashboard_v3", timeout=15)
    must("dashboard_v3 HTTP 200", c == 200, f"HTTP={c} body={b[:220]}")
    j = load_json(b)
    must("dashboard_v3 ok==true", j.get("ok") is True, b[:220])
    bysev = j.get("by_severity") or (j.get("summary_all") or {}).get("by_severity")
    must("dashboard_v3 has by_severity", isinstance(bysev, dict), b[:300])

    # 3) runs index resolved
    c, b = get("/api/vsp/runs_index_v3_fs_resolved?limit=5&hide_empty=0&filter=1", timeout=15)
    must("runs_index_v3_fs_resolved HTTP 200", c == 200, f"HTTP={c} body={b[:220]}")
    j = load_json(b)
    must("runs_index_v3_fs_resolved items is list", isinstance(j.get("items"), list), b[:300])

    # 4) settings/rule_overrides/datasource must return JSON object (even if empty)
    for path in ["/api/vsp/settings_v1", "/api/vsp/rule_overrides_v1", "/api/vsp/datasource_v2?limit=10"]:
        c, b = get(path, timeout=15)
        must(f"{path} HTTP 200", c == 200, f"HTTP={c} body={b[:220]}")
        j = load_json(b)
        must(f"{path} is JSON object", isinstance(j, dict), b[:220])

    # 5) status latest (may be ok true/false)
    c, b = get("/api/vsp/run_status_latest", timeout=15)
    must("run_status_latest HTTP 200", c == 200, f"HTTP={c} body={b[:220]}")
    j = load_json(b)
    must("run_status_latest is object", isinstance(j, dict), b[:220])

    # 6) template sanity: duplicate script src
    tpl = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/vsp_dashboard_2025.html")
    if tpl.exists():
        t = tpl.read_text(encoding="utf-8", errors="ignore")
        srcs = re.findall(r'<script[^>]+src="([^"]+)"', t, flags=re.I)
        dups = sorted({s for s in srcs if srcs.count(s) > 1})
        if dups:
            must("no duplicate <script src>", False, "dup=" + dups[0])
        else:
            print("[OK] no duplicate <script src>")
    else:
        warn("template vsp_dashboard_2025.html not found (skip)")

    print("[GATE] PASS")

if __name__ == "__main__":
    main()
