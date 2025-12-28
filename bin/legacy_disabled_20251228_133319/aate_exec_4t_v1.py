#!/usr/bin/env python3
# AATE EXEC 4T V1: generate suite files + execute basic checks + verdict_4t.json
# Output:
#   <run_dir>/tests/{ui_tests,api_tests,sec_tests,perf_tests}.json
#   <run_dir>/results/{ui_results,api_results,sec_results,perf_results}.json
#   <run_dir>/verdict_4t.json
import argparse, json, os, sys, time, re
from pathlib import Path
from datetime import datetime, timezone
from urllib.parse import urljoin, urlparse
import urllib.request

SCHEMA_VERDICT = "aate.verdict_4t.v1"

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def read_json(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None

def write_json(p: Path, obj):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")

def http_get(url: str, headers=None, timeout=20):
    req = urllib.request.Request(url, method="GET")
    for k,v in (headers or {}).items():
        req.add_header(k, v)
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read(200_000)
            dur = time.time() - start
            return {
                "ok": True,
                "status": getattr(resp, "status", 200),
                "elapsed_ms": int(dur*1000),
                "len": len(body),
            }
    except Exception as e:
        dur = time.time() - start
        return {"ok": False, "error": str(e), "elapsed_ms": int(dur*1000)}

def pick_base_url(run_dir: Path, gen_ready: dict):
    # Prefer manifest base_url, else infer from any view URL
    base = gen_ready.get("base_url")
    if base:
        return base.rstrip("/")
    views = read_json(run_dir / "ui_dom_views_any.json") or read_json(run_dir / "evidence/ui_dom_views_any.json")
    if isinstance(views, dict):
        for _, v in views.items():
            if isinstance(v, dict) and v.get("url"):
                u = v["url"]
                pr = urlparse(u)
                return f"{pr.scheme}://{pr.netloc}"
    return None

def load_or_pack(run_dir: Path, profile: str):
    gen_path = run_dir / "gen_ready_4t.json"
    gen = read_json(gen_path)
    if gen:
        return gen
    # If packer exists, run it
    packer = run_dir.parent.parent / "bin/aate_pack_run_v2.py"  # best-effort (if run from project root/out/<run_id>)
    if packer.exists():
        os.system(f"python3 {packer} {run_dir} --profile {profile} >/dev/null 2>&1 || true")
        gen = read_json(gen_path)
    return gen

def generate_ui_suite(run_dir: Path, base_url: str):
    # Minimal suite: reachability checks for a few routes (commercial: better plug into your UI engine later)
    views = read_json(run_dir / "ui_dom_views_any.json") or read_json(run_dir / "evidence/ui_dom_views_any.json") or {}
    routes = []
    if isinstance(views, dict):
        for _, v in views.items():
            if isinstance(v, dict) and v.get("url"):
                routes.append(v["url"])
    # Dedup & pick up to 3
    uniq = []
    for u in routes:
        if u not in uniq:
            uniq.append(u)
    picked = uniq[:3]
    if not picked and base_url:
        picked = [base_url + "/"]

    suite = {"schema":"aate.ui_tests.v1", "generated_at": now_iso(), "checks":[]}
    for u in picked:
        suite["checks"].append({"type":"http_get", "url": u, "expect_status_in":[200, 204, 302, 303]})
    return suite

def extract_api_endpoints(run_dir: Path, base_url: str):
    api_catalog = read_json(run_dir / "api_catalog.json") or read_json(run_dir / "evidence/api_catalog.json")
    net_sum = read_json(run_dir / "net_summary.json") or read_json(run_dir / "evidence/net_summary.json") or read_json(run_dir / "api_calls_har.json") or read_json(run_dir / "evidence/api_calls_har.json")

    endpoints = []

    if isinstance(api_catalog, dict) and "endpoints" in api_catalog and isinstance(api_catalog["endpoints"], list):
        for e in api_catalog["endpoints"][:20]:
            if isinstance(e, dict) and e.get("url"):
                endpoints.append(e["url"])
    elif isinstance(api_catalog, dict) and "paths" in api_catalog and isinstance(api_catalog["paths"], dict):
        for pth in list(api_catalog["paths"].keys())[:20]:
            if base_url:
                endpoints.append(urljoin(base_url + "/", pth.lstrip("/")))
    elif isinstance(api_catalog, list):
        for e in api_catalog[:20]:
            if isinstance(e, str):
                endpoints.append(e)
            elif isinstance(e, dict) and e.get("url"):
                endpoints.append(e["url"])

    if not endpoints and isinstance(net_sum, dict):
        # try to infer from requests list
        reqs = None
        if isinstance(net_sum.get("requests"), list):
            reqs = net_sum["requests"]
        elif isinstance(net_sum.get("items"), list):
            reqs = net_sum["items"]
        if reqs:
            for r in reqs[:50]:
                u = r.get("url") if isinstance(r, dict) else None
                if u: endpoints.append(u)

    # normalize: keep only same origin if base_url provided
    if base_url:
        prb = urlparse(base_url)
        origin = f"{prb.scheme}://{prb.netloc}"
        endpoints2 = []
        for u in endpoints:
            try:
                pru = urlparse(u)
                if pru.scheme and pru.netloc:
                    if f"{pru.scheme}://{pru.netloc}" == origin:
                        endpoints2.append(u)
                else:
                    endpoints2.append(urljoin(origin + "/", u.lstrip("/")))
            except Exception:
                pass
        endpoints = endpoints2

    # dedup
    uniq = []
    for u in endpoints:
        if u not in uniq:
            uniq.append(u)
    return uniq[:10]

def generate_api_suite(run_dir: Path, base_url: str):
    endpoints = extract_api_endpoints(run_dir, base_url)
    suite = {"schema":"aate.api_tests.v1", "generated_at": now_iso(), "requests":[]}
    for u in endpoints:
        suite["requests"].append({"method":"GET", "url": u, "expect_status_in":[200,204,301,302,401,403]})
    return suite

def generate_sec_suite(run_dir: Path):
    # Minimal: reference existing findings files (commercial: later plug tools execution here)
    suite = {"schema":"aate.sec_tests.v1", "generated_at": now_iso(), "inputs":[]}
    for rel in ["findings_unified.json","reports/findings_unified.json","sec_basic.json","sec_samples.json"]:
        p = run_dir / rel
        if p.exists():
            suite["inputs"].append({"type":"json", "path": str(p)})
    if not suite["inputs"]:
        suite["inputs"].append({"type":"none", "note":"no sec inputs found; will degrade"})
    return suite

def generate_perf_suite(run_dir: Path, base_url: str):
    api_eps = extract_api_endpoints(run_dir, base_url)
    views = read_json(run_dir / "ui_dom_views_any.json") or read_json(run_dir / "evidence/ui_dom_views_any.json") or {}
    routes = []
    if isinstance(views, dict):
        for _, v in views.items():
            if isinstance(v, dict) and v.get("url"):
                routes.append(v["url"])
    uniq = []
    for u in (routes + api_eps):
        if u not in uniq:
            uniq.append(u)
    picked = uniq[:5] if uniq else ([base_url + "/"] if base_url else [])
    suite = {"schema":"aate.perf_tests.v1", "generated_at": now_iso(), "scenarios":[]}
    for u in picked:
        suite["scenarios"].append({
            "type":"http_get_timing",
            "url": u,
            "runs": 3,
            "thresholds": {"p95_ms": 4000, "error_rate": 0.2}
        })
    return suite

def run_ui(suite):
    results = {"schema":"aate.ui_results.v1", "ran_at": now_iso(), "checks":[], "summary":{"pass":0,"fail":0,"error":0}}
    for c in suite.get("checks", []):
        u = c.get("url")
        rsp = http_get(u, timeout=25)
        ok = rsp["ok"] and (rsp.get("status") in c.get("expect_status_in", [200]))
        item = {"url":u, "resp":rsp, "ok":ok}
        results["checks"].append(item)
        if ok: results["summary"]["pass"] += 1
        elif rsp["ok"]: results["summary"]["fail"] += 1
        else: results["summary"]["error"] += 1
    return results

def run_api(suite, headers=None):
    results = {"schema":"aate.api_results.v1", "ran_at": now_iso(), "requests":[], "summary":{"pass":0,"fail":0,"error":0}}
    for r in suite.get("requests", []):
        u = r.get("url")
        rsp = http_get(u, headers=headers, timeout=25)
        ok = rsp["ok"] and (rsp.get("status") in r.get("expect_status_in", [200]))
        item = {"method":"GET", "url":u, "resp":rsp, "ok":ok}
        results["requests"].append(item)
        if ok: results["summary"]["pass"] += 1
        elif rsp["ok"]: results["summary"]["fail"] += 1
        else: results["summary"]["error"] += 1
    return results

def run_perf(suite, headers=None):
    import statistics
    results = {"schema":"aate.perf_results.v1", "ran_at": now_iso(), "scenarios":[], "summary":{"ok":0,"bad":0,"error":0}}
    for sc in suite.get("scenarios", []):
        u = sc.get("url")
        runs = int(sc.get("runs", 3))
        times = []
        errors = 0
        for _ in range(runs):
            rsp = http_get(u, headers=headers, timeout=30)
            if rsp["ok"]:
                times.append(rsp.get("elapsed_ms", 0))
            else:
                errors += 1
        p95 = int(statistics.quantiles(times, n=20)[-1]) if len(times) >= 2 else (times[0] if times else 0)
        err_rate = errors / float(runs) if runs else 1.0
        th = sc.get("thresholds", {})
        ok = (p95 <= int(th.get("p95_ms", 999999))) and (err_rate <= float(th.get("error_rate", 1.0)))
        results["scenarios"].append({"url":u,"runs":runs,"p95_ms":p95,"error_rate":err_rate,"ok":ok})
        if ok: results["summary"]["ok"] += 1
        elif errors == runs: results["summary"]["error"] += 1
        else: results["summary"]["bad"] += 1
    return results

def run_sec_from_existing(run_dir: Path):
    # Basic verdict from findings_unified.json if exists
    findings = read_json(run_dir / "findings_unified.json") or read_json(run_dir / "reports/findings_unified.json")
    counts = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}
    n = 0
    if isinstance(findings, list):
        for f in findings:
            if isinstance(f, dict):
                sev = str(f.get("severity","")).upper()
                if sev in counts: counts[sev] += 1
                n += 1
    elif isinstance(findings, dict):
        # try common shapes
        arr = findings.get("items") if isinstance(findings.get("items"), list) else findings.get("findings")
        if isinstance(arr, list):
            for f in arr:
                if isinstance(f, dict):
                    sev = str(f.get("severity","")).upper()
                    if sev in counts: counts[sev] += 1
                    n += 1
    return {"schema":"aate.sec_results.v1", "ran_at": now_iso(), "counts":counts, "total":n, "source":"findings_unified.json" if findings else None}

def verdict_from_type(profile, type_name, ready_flag, hard_blockers, soft_missing, result_obj, required):
    # Status values: PASS | AMBER | FAIL | NOT_READY | SKIPPED
    if any(b.get("type")==type_name for b in hard_blockers):
        return "FAIL", [b for b in hard_blockers if b.get("type")==type_name]

    if not ready_flag:
        # commercial default: NOT_READY => AMBER at group unless STRICT; per-target we keep NOT_READY
        return "NOT_READY", [m for m in soft_missing if m.get("type")==type_name]

    # If we couldn't execute, mark SKIPPED
    if result_obj is None:
        return "SKIPPED", [{"type":type_name,"code":"NO_RUNNER","msg":"no executor available for this type"}]

    # Basic eval per type
    if type_name in ("UI","API"):
        summ = result_obj.get("summary", {})
        if summ.get("error", 0) > 0:
            return "AMBER", [{"type":type_name,"code":"HTTP_ERRORS","msg":"some checks errored"}]
        if summ.get("fail", 0) > 0:
            # In FULL we treat functional failures as FAIL
            return ("FAIL" if profile=="FULL" else "AMBER"), [{"type":type_name,"code":"CHECK_FAILED","msg":"some checks failed"}]
        return "PASS", []
    if type_name == "PERF":
        summ = result_obj.get("summary", {})
        if summ.get("error",0) > 0:
            return "AMBER", [{"type":"PERF","code":"PERF_ERRORS","msg":"perf scenarios errored"}]
        if summ.get("bad",0) > 0:
            return ("FAIL" if profile=="FULL" else "AMBER"), [{"type":"PERF","code":"PERF_THRESH","msg":"perf thresholds not met"}]
        return "PASS", []
    if type_name == "SEC":
        c = result_obj.get("counts", {})
        crit = int(c.get("CRITICAL",0)); high = int(c.get("HIGH",0))
        if crit > 0:
            return "FAIL", [{"type":"SEC","code":"CRITICAL_FINDINGS","msg":f"CRITICAL={crit}"}]
        if high > 0:
            return ("FAIL" if profile=="FULL" else "AMBER"), [{"type":"SEC","code":"HIGH_FINDINGS","msg":f"HIGH={high}"}]
        return "PASS", []
    return "AMBER", [{"type":type_name,"code":"UNKNOWN_TYPE","msg":"unknown evaluation"}]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir", help="out/<run_id> directory")
    ap.add_argument("--profile", default="", help="SMOKE|FULL (default from AATE_GATE_PROFILE or FULL)")
    ap.add_argument("--strict-not-ready", action="store_true", help="If set: NOT_READY for required types becomes FAIL overall")
    args = ap.parse_args()

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.exists():
        print(f"[ERR] run_dir not found: {run_dir}", file=sys.stderr)
        return 2

    profile = (args.profile or os.environ.get("AATE_GATE_PROFILE","FULL")).strip().upper() or "FULL"

    gen = load_or_pack(run_dir, profile)
    if not gen:
        print("[ERR] missing gen_ready_4t.json and cannot auto-pack", file=sys.stderr)
        return 3

    base_url = pick_base_url(run_dir, gen)
    hard_blockers = gen.get("hard_blockers", [])
    soft_missing = gen.get("soft_missing", [])
    ready = gen.get("ready", {})

    tests_dir = run_dir / "tests"
    results_dir = run_dir / "results"
    tests_dir.mkdir(parents=True, exist_ok=True)
    results_dir.mkdir(parents=True, exist_ok=True)

    # Required types per profile (commercial default)
    required_types = ["UI"] if profile=="SMOKE" else ["UI","API","SEC","PERF"]

    # === Generate suites ===
    ui_suite = generate_ui_suite(run_dir, base_url) if base_url else {"schema":"aate.ui_tests.v1","generated_at":now_iso(),"checks":[]}
    api_suite = generate_api_suite(run_dir, base_url) if base_url else {"schema":"aate.api_tests.v1","generated_at":now_iso(),"requests":[]}
    sec_suite = generate_sec_suite(run_dir)
    perf_suite = generate_perf_suite(run_dir, base_url) if base_url else {"schema":"aate.perf_tests.v1","generated_at":now_iso(),"scenarios":[]}

    write_json(tests_dir / "ui_tests.json", ui_suite)
    write_json(tests_dir / "api_tests.json", api_suite)
    write_json(tests_dir / "sec_tests.json", sec_suite)
    write_json(tests_dir / "perf_tests.json", perf_suite)

    # === Execute basic runners ===
    # Auth headers (optional)
    auth_seed = read_json(run_dir / "auth_seed.json") or read_json(run_dir / "evidence/auth_seed.json") or {}
    headers = auth_seed.get("headers") if isinstance(auth_seed, dict) else None
    if not isinstance(headers, dict):
        headers = None

    ui_res = None
    api_res = None
    perf_res = None
    sec_res = None

    if ready.get("UI"):
        ui_res = run_ui(ui_suite) if ui_suite.get("checks") else None
        if ui_res: write_json(results_dir / "ui_results.json", ui_res)

    if ready.get("API"):
        api_res = run_api(api_suite, headers=headers) if api_suite.get("requests") else None
        if api_res: write_json(results_dir / "api_results.json", api_res)

    if ready.get("PERF"):
        perf_res = run_perf(perf_suite, headers=headers) if perf_suite.get("scenarios") else None
        if perf_res: write_json(results_dir / "perf_results.json", perf_res)

    if ready.get("SEC"):
        sec_res = run_sec_from_existing(run_dir)
        write_json(results_dir / "sec_results.json", sec_res)

    # === Verdict per type ===
    per_type = {}
    reasons = []

    for tname, r_obj in [("UI",ui_res),("API",api_res),("SEC",sec_res),("PERF",perf_res)]:
        status, rs = verdict_from_type(profile, tname, bool(ready.get(tname)), hard_blockers, soft_missing, r_obj, (tname in required_types))
        per_type[tname] = {"status": status}
        if rs:
            per_type[tname]["reasons"] = rs
            reasons += rs

    # === Overall ===
    # FAIL if any per-type FAIL
    overall = "PASS"
    if any(per_type[t]["status"] == "FAIL" for t in per_type):
        overall = "FAIL"
    else:
        # if required types not executed/ready => AMBER (or FAIL when strict-not-ready)
        for rt in required_types:
            st = per_type.get(rt, {}).get("status")
            if st in ("NOT_READY","SKIPPED"):
                overall = "FAIL" if args.strict_not_ready else "AMBER"
                break
        if overall == "PASS":
            # if any AMBER in any type => AMBER
            if any(per_type[t]["status"] == "AMBER" for t in per_type):
                overall = "AMBER"

    verdict = {
        "schema": SCHEMA_VERDICT,
        "ts": now_iso(),
        "run_id": gen.get("run_id"),
        "target_id": gen.get("target_id"),
        "gate_profile": profile,
        "base_url": base_url,
        "required_types": required_types,
        "per_type": per_type,
        "overall": overall,
        "reasons": reasons,
        "notes": [
            "UI/API/PERF executors here are basic HTTP checks. Plug real UI/API runners later.",
            "SEC verdict is derived from existing findings_unified.json if present."
        ]
    }

    write_json(run_dir / "verdict_4t.json", verdict)
    print(f"[OK] wrote {run_dir / 'verdict_4t.json'} (overall={overall})")
    return 0 if overall=="PASS" else (10 if overall=="AMBER" else 20)

if __name__ == "__main__":
    raise SystemExit(main())
