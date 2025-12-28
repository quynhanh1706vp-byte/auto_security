#!/usr/bin/env python3
import os, json, glob

ROOT = os.environ.get("ROOT", "/home/test/Data/SECURITY_BUNDLE")
OUT_DIR = os.path.join(ROOT, "out")

def latest_run():
    if not os.path.isdir(OUT_DIR):
        return None
    runs = [os.path.join(OUT_DIR, d) for d in os.listdir(OUT_DIR) if d.startswith("RUN_")]
    if not runs:
        return None
    return sorted(runs)[-1]

def load_json_safely(path):
    """Thử JSON chuẩn, nếu fail thử JSON Lines."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        items = []
        try:
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        items.append(json.loads(line))
                    except Exception:
                        pass
        except Exception:
            pass
        return items or None

def load_findings_for_run(run_path):
    report_dir = os.path.join(run_path, "report")
    if not os.path.isdir(report_dir):
        return [], None

    candidates = []
    for pat in ["findings_unified.json", "findings.json", "findings_all.json",
                "*finding*.json", "*findings*.json"]:
        candidates.extend(glob.glob(os.path.join(report_dir, pat)))

    seen = set()
    candidates = [c for c in candidates if not (c in seen or seen.add(c))]

    chosen_path = None
    findings_raw = None
    for fp in candidates:
        data = load_json_safely(fp)
        if data is None:
            continue
        chosen_path = fp
        findings_raw = data
        break

    if findings_raw is None:
        return [], None

    if isinstance(findings_raw, list):
        return findings_raw, chosen_path

    if isinstance(findings_raw, dict):
        for key in ("findings", "items", "rows", "data", "results"):
            val = findings_raw.get(key)
            if isinstance(val, list):
                return val, chosen_path

    return [], chosen_path

if __name__ == "__main__":
    run = os.environ.get("RUN") or latest_run()
    print("[RUN]", run)
    if not run:
        raise SystemExit("Không tìm thấy RUN trong out/")
    findings, path = load_findings_for_run(run)
    print("[PATH]", path)
    print("[LEN]", len(findings))
    print("[SAMPLE]", findings[:3])
