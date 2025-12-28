#!/usr/bin/env python3
# AATE PACK RUN V2: build per-target GEN_READY_4T contract
# Output: <run_dir>/gen_ready_4t.json
import argparse, json, os, re, sys
from pathlib import Path
from datetime import datetime, timezone

SCHEMA = "aate.gen_ready_4t.v1"

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def read_text(p: Path, max_bytes=2_000_000) -> str:
    try:
        b = p.read_bytes()
        if len(b) > max_bytes:
            b = b[-max_bytes:]
        return b.decode("utf-8", errors="ignore")
    except Exception:
        return ""

def read_json(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None

def count_json_entries(obj) -> int:
    if obj is None:
        return 0
    if isinstance(obj, list):
        return len(obj)
    if isinstance(obj, dict):
        return len(obj.keys())
    return 0

def count_jsonl_lines(p: Path) -> int:
    try:
        n = 0
        with p.open("rb") as f:
            for _ in f:
                n += 1
        return n
    except Exception:
        return 0

def find_first(run_dir: Path, rel_candidates):
    for rel in rel_candidates:
        p = run_dir / rel
        if p.exists():
            return p
    return None

def infer_profile(args_profile: str) -> str:
    if args_profile:
        return args_profile.upper()
    env = os.environ.get("AATE_GATE_PROFILE", "").strip().upper()
    if env:
        return env
    return "FULL"

def thresholds_for(profile: str):
    # commercial defaults (tune later via env if needed)
    if profile == "SMOKE":
        return {
            "UI": {"min_views": 1, "min_steps": 1},
            "API": {"min_endpoints": 1},
            "SEC": {"min_samples": 1},
            "PERF": {"min_scenarios": 1},
        }
    # FULL
    return {
        "UI": {"min_views": 10, "min_steps": 5},
        "API": {"min_endpoints": 3},
        "SEC": {"min_samples": 1},
        "PERF": {"min_scenarios": 2},
    }

def ui_ready(run_dir: Path, th):
    hard, soft = [], []
    evidence = {}

    ui_log = find_first(run_dir, ["evidence/ui_engine.log", "ui_engine.log", "artifacts/ui_engine.log"])
    trace_zip = find_first(run_dir, ["artifacts/trace.zip", "trace.zip", "evidence/trace.zip"])
    views = find_first(run_dir, ["ui_dom_views_any.json", "evidence/ui_dom_views_any.json", "ui_dom_views.json"])
    steps = find_first(run_dir, ["evidence/steps_log.jsonl", "steps_log.jsonl"])

    login_ok = None
    trace_ok = bool(trace_zip and trace_zip.exists())

    if ui_log and ui_log.exists():
        t = read_text(ui_log)
        # Try to parse login_ok from log patterns (best-effort)
        m = re.search(r"login_ok['\"]?\s*:\s*(true|false)", t, re.IGNORECASE)
        if m:
            login_ok = (m.group(1).lower() == "true")
        else:
            # sometimes printed as dict: {'login_ok': True}
            m2 = re.search(r"\{\s*'login_ok'\s*:\s*(True|False)", t)
            if m2:
                login_ok = (m2.group(1) == "True")

    views_total = 0
    if views and views.exists():
        v = read_json(views)
        views_total = count_json_entries(v)

    steps_total = 0
    if steps and steps.exists():
        steps_total = count_jsonl_lines(steps)

    evidence.update({
        "ui_log": str(ui_log) if ui_log else None,
        "trace_zip": str(trace_zip) if trace_zip else None,
        "views_file": str(views) if views else None,
        "steps_file": str(steps) if steps else None,
        "login_ok": login_ok,
        "trace_ok": trace_ok,
        "views_total": views_total,
        "steps_total": steps_total,
    })

    # Hard prerequisites (commercial)
    if login_ok is False:
        hard.append({"type":"UI", "code":"LOGIN_FAILED", "msg":"login_ok=false"})
    if login_ok is None:
        soft.append({"type":"UI", "code":"LOGIN_UNKNOWN", "msg":"cannot determine login_ok from logs"})
    if not trace_ok:
        soft.append({"type":"UI", "code":"TRACE_MISSING", "msg":"trace.zip missing (degrade)"} )

    if views_total < th["min_views"]:
        soft.append({"type":"UI", "code":"VIEWS_LOW", "msg":f"views_total({views_total}) < min_views({th['min_views']})"})
    if steps_total < th["min_steps"]:
        soft.append({"type":"UI", "code":"STEPS_LOW", "msg":f"steps_total({steps_total}) < min_steps({th['min_steps']})"})

    # Ready if no hard blockers AND basic seeds ok-ish
    ready = (len(hard) == 0) and ((views_total >= th["min_views"]) or trace_ok or (ui_log is not None))
    return ready, hard, soft, evidence

def api_ready(run_dir: Path, th):
    hard, soft = [], []
    evidence = {}

    api_catalog = find_first(run_dir, ["api_catalog.json", "evidence/api_catalog.json", "api/api_catalog.json"])
    net_sum = find_first(run_dir, ["net_summary.json", "evidence/net_summary.json", "api_calls_har.json", "evidence/api_calls_har.json"])
    auth_seed = find_first(run_dir, ["auth_seed.json", "evidence/auth_seed.json", "api/auth_seed.json"])

    endpoints_total = 0
    src = None

    if api_catalog and api_catalog.exists():
        obj = read_json(api_catalog)
        # support common shapes:
        # { endpoints:[...] } or { paths:{...} } or [...]
        if isinstance(obj, dict) and "endpoints" in obj and isinstance(obj["endpoints"], list):
            endpoints_total = len(obj["endpoints"])
        elif isinstance(obj, dict) and "paths" in obj and isinstance(obj["paths"], dict):
            endpoints_total = len(obj["paths"].keys())
        else:
            endpoints_total = count_json_entries(obj)
        src = str(api_catalog)

    elif net_sum and net_sum.exists():
        obj = read_json(net_sum)
        # support: {requests:[{url,...}]} or {items:[...]} etc.
        if isinstance(obj, dict) and "requests" in obj and isinstance(obj["requests"], list):
            urls = []
            for r in obj["requests"]:
                u = r.get("url") if isinstance(r, dict) else None
                if u: urls.append(u)
            endpoints_total = len(set(urls)) if urls else len(obj["requests"])
        elif isinstance(obj, dict) and "items" in obj and isinstance(obj["items"], list):
            endpoints_total = len(obj["items"])
        else:
            endpoints_total = count_json_entries(obj)
        src = str(net_sum)

    evidence.update({
        "api_catalog": str(api_catalog) if api_catalog else None,
        "net_summary_like": str(net_sum) if net_sum else None,
        "auth_seed": str(auth_seed) if auth_seed else None,
        "endpoints_total": endpoints_total,
        "endpoints_src": src,
        "has_auth_seed": bool(auth_seed and auth_seed.exists()),
    })

    if endpoints_total < th["min_endpoints"]:
        soft.append({"type":"API","code":"ENDPOINTS_LOW","msg":f"endpoints_total({endpoints_total}) < min_endpoints({th['min_endpoints']})"})
    if not (auth_seed and auth_seed.exists()):
        soft.append({"type":"API","code":"AUTH_SEED_MISSING","msg":"no auth_seed.json (will run public-only / degrade)"})

    ready = (len(hard) == 0) and (endpoints_total >= 1)
    return ready, hard, soft, evidence

def sec_ready(run_dir: Path, th):
    hard, soft = [], []
    evidence = {}
    sec_samples = find_first(run_dir, ["sec_samples.json", "evidence/sec_samples.json", "sec/sec_samples.json"])
    sec_basic = find_first(run_dir, ["sec_basic.json", "evidence/sec_basic.json"])
    findings = find_first(run_dir, ["findings_unified.json", "reports/findings_unified.json", "evidence/findings_unified.json"])
    allowlist = find_first(run_dir, ["sec_allowlist.json", "baseline/allowlist.json", "evidence/sec_allowlist.json"])

    samples_total = 0
    src = None
    if sec_samples and sec_samples.exists():
        obj = read_json(sec_samples)
        samples_total = count_json_entries(obj)
        src = str(sec_samples)
    elif sec_basic and sec_basic.exists():
        obj = read_json(sec_basic)
        # {samples:[...]} or any dict/list
        if isinstance(obj, dict) and "samples" in obj and isinstance(obj["samples"], list):
            samples_total = len(obj["samples"])
        else:
            samples_total = count_json_entries(obj)
        src = str(sec_basic)
    elif findings and findings.exists():
        # treat existing findings as "seed exists" (basic)
        obj = read_json(findings)
        samples_total = count_json_entries(obj)
        src = str(findings)

    evidence.update({
        "sec_samples": str(sec_samples) if sec_samples else None,
        "sec_basic": str(sec_basic) if sec_basic else None,
        "findings_unified": str(findings) if findings else None,
        "allowlist": str(allowlist) if allowlist else None,
        "samples_total": samples_total,
        "samples_src": src,
        "has_allowlist": bool(allowlist and allowlist.exists()),
    })

    if samples_total < th["min_samples"]:
        soft.append({"type":"SEC","code":"SAMPLES_LOW","msg":f"samples_total({samples_total}) < min_samples({th['min_samples']})"})
    if not (allowlist and allowlist.exists()):
        soft.append({"type":"SEC","code":"ALLOWLIST_MISSING","msg":"no allowlist/baseline (verdict may be noisy)"} )

    ready = (len(hard) == 0) and (samples_total >= 1 or (findings and findings.exists()))
    return ready, hard, soft, evidence

def perf_ready(run_dir: Path, th):
    hard, soft = [], []
    evidence = {}
    perf_seed = find_first(run_dir, ["perf_seed.json", "evidence/perf_seed.json", "perf/perf_seed.json"])
    net_sum = find_first(run_dir, ["net_summary.json", "evidence/net_summary.json"])
    views = find_first(run_dir, ["ui_dom_views_any.json", "evidence/ui_dom_views_any.json"])

    scenarios_total = 0
    src = None
    if perf_seed and perf_seed.exists():
        obj = read_json(perf_seed)
        # {scenarios:[...]} or list
        if isinstance(obj, dict) and "scenarios" in obj and isinstance(obj["scenarios"], list):
            scenarios_total = len(obj["scenarios"])
        else:
            scenarios_total = count_json_entries(obj)
        src = str(perf_seed)
    else:
        # infer minimal scenarios from net_summary + views
        inferred = 0
        if net_sum and net_sum.exists():
            inferred += 1
        if views and views.exists():
            inferred += 1
        scenarios_total = inferred
        src = "inferred(net_summary/views)" if inferred else None

    evidence.update({
        "perf_seed": str(perf_seed) if perf_seed else None,
        "net_summary": str(net_sum) if net_sum else None,
        "views_file": str(views) if views else None,
        "scenarios_total": scenarios_total,
        "scenarios_src": src,
    })

    if scenarios_total < th["min_scenarios"]:
        soft.append({"type":"PERF","code":"SCENARIOS_LOW","msg":f"scenarios_total({scenarios_total}) < min_scenarios({th['min_scenarios']})"})

    ready = (len(hard) == 0) and (scenarios_total >= 1)
    return ready, hard, soft, evidence

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir", help="out/<run_id> directory")
    ap.add_argument("--profile", default="", help="SMOKE|FULL (default from AATE_GATE_PROFILE or FULL)")
    ap.add_argument("--out", default="", help="output json path (default <run_dir>/gen_ready_4t.json)")
    args = ap.parse_args()

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.exists():
        print(f"[ERR] run_dir not found: {run_dir}", file=sys.stderr)
        return 2

    profile = infer_profile(args.profile)
    th = thresholds_for(profile)

    # Optional manifest
    manifest = read_json(run_dir / "run_manifest.json") or {}
    run_id = manifest.get("run_id") or run_dir.name
    target_id = manifest.get("target_id") or manifest.get("target") or manifest.get("profile") or "UNKNOWN_TARGET"
    base_url = manifest.get("base_url") or manifest.get("BASE_URL") or None

    ready = {}
    hard_blockers = []
    soft_missing = []
    evidence = {}

    r_ui, h_ui, s_ui, e_ui = ui_ready(run_dir, th["UI"])
    ready["UI"] = bool(r_ui)
    hard_blockers += h_ui
    soft_missing += s_ui
    evidence["UI"] = e_ui

    r_api, h_api, s_api, e_api = api_ready(run_dir, th["API"])
    ready["API"] = bool(r_api)
    hard_blockers += h_api
    soft_missing += s_api
    evidence["API"] = e_api

    r_sec, h_sec, s_sec, e_sec = sec_ready(run_dir, th["SEC"])
    ready["SEC"] = bool(r_sec)
    hard_blockers += h_sec
    soft_missing += s_sec
    evidence["SEC"] = e_sec

    r_perf, h_perf, s_perf, e_perf = perf_ready(run_dir, th["PERF"])
    ready["PERF"] = bool(r_perf)
    hard_blockers += h_perf
    soft_missing += s_perf
    evidence["PERF"] = e_perf

    # commercial: overall readiness means "can generate something for all 4T"
    ready_4t = all(bool(ready.get(k)) for k in ["UI","API","SEC","PERF"])

    out = {
        "schema": SCHEMA,
        "ts": now_iso(),
        "run_id": run_id,
        "target_id": target_id,
        "base_url": base_url,
        "gate_profile": profile,
        "ready": ready,
        "ready_4t": ready_4t,
        "thresholds": th,
        "hard_blockers": hard_blockers,
        "soft_missing": soft_missing,
        "degraded": [],   # reserved: tool timeout/missing signals if you add later
        "evidence": evidence,
    }

    out_path = Path(args.out).resolve() if args.out else (run_dir / "gen_ready_4t.json")
    out_path.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[OK] wrote {out_path}")

    # exit code: 0 if ready_4t true; 10 if not ready but no hard blockers; 20 if hard blockers
    if hard_blockers:
        return 20
    if not ready_4t:
        return 10
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
