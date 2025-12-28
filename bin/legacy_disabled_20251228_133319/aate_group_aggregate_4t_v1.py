#!/usr/bin/env python3
# Aggregate N targets (run_dirs) -> group summary 4T
# Output: group_summary_4t.json
import argparse, json, sys
from pathlib import Path
from datetime import datetime, timezone

SCHEMA = "aate.group_summary_4t.v1"

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def read_json(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--request-id", required=True, help="group request id")
    ap.add_argument("--out", required=True, help="output json path")
    ap.add_argument("run_dirs", nargs="+", help="list of out/<run_id> dirs (N targets)")
    args = ap.parse_args()

    items = []
    ready_targets = []
    not_ready_targets = []
    pass_targets = []
    amber_targets = []
    fail_targets = []

    for rd in args.run_dirs:
        run_dir = Path(rd).resolve()
        gen = read_json(run_dir / "gen_ready_4t.json") or {}
        ver = read_json(run_dir / "verdict_4t.json") or {}

        run_id = gen.get("run_id") or ver.get("run_id") or run_dir.name
        target_id = gen.get("target_id") or ver.get("target_id") or "UNKNOWN_TARGET"

        gen_ready_4t = bool(gen.get("ready_4t", False))
        verdict = ver.get("overall") or "NO_VERDICT"

        item = {
            "target_id": target_id,
            "run_id": run_id,
            "gen_ready_4t": gen_ready_4t,
            "verdict_overall": verdict,
            "ready": gen.get("ready"),
            "hard_blockers": gen.get("hard_blockers", []),
            "soft_missing": gen.get("soft_missing", []),
            "per_type": ver.get("per_type"),
            "required_types": ver.get("required_types"),
        }
        items.append(item)

        if gen_ready_4t:
            ready_targets.append(target_id)
        else:
            not_ready_targets.append({"target_id": target_id, "run_id": run_id, "reasons": gen.get("hard_blockers", []) + gen.get("soft_missing", [])})

        if verdict == "PASS":
            pass_targets.append(target_id)
        elif verdict == "FAIL":
            fail_targets.append(target_id)
        elif verdict == "AMBER":
            amber_targets.append(target_id)

    # group overall policy (commercial default)
    if fail_targets:
        group_overall = "FAIL"
    else:
        if not_ready_targets:
            group_overall = "AMBER"
        else:
            group_overall = "AMBER" if amber_targets else "PASS"

    out = {
        "schema": SCHEMA,
        "ts": now_iso(),
        "request_id": args.request_id,
        "n_targets": len(items),
        "ready_targets": ready_targets,
        "not_ready_targets": not_ready_targets,
        "pass_targets": pass_targets,
        "amber_targets": amber_targets,
        "fail_targets": fail_targets,
        "group_overall_4t": group_overall,
        "items": items,
    }

    out_path = Path(args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[OK] wrote {out_path} (group_overall_4t={group_overall})")
    return 0 if group_overall=="PASS" else (10 if group_overall=="AMBER" else 20)

if __name__ == "__main__":
    raise SystemExit(main())
