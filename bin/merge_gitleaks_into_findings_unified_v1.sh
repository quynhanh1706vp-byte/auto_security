#!/usr/bin/env bash
set -euo pipefail

CI_DIR="${1:-}"
if [ -z "$CI_DIR" ]; then
  RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -er '.items[0].run_id')"
  CI_DIR="$(curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq -r '.ci_run_dir // empty')"
fi

[ -n "$CI_DIR" ] || { echo "[ERR] missing CI_DIR"; exit 2; }
[ -d "$CI_DIR" ] || { echo "[ERR] CI_DIR not found: $CI_DIR"; exit 2; }
echo "[CI] $CI_DIR"

GL="$CI_DIR/gitleaks/gitleaks.json"
[ -f "$GL" ] || { echo "[ERR] missing $GL"; exit 3; }

F1="$CI_DIR/findings_unified.json"
F2="$CI_DIR/reports/findings_unified.json"

python3 - "$CI_DIR" "$GL" "$F1" "$F2" <<'PY'
import json, sys, os, hashlib, datetime

ci, gl_path, f1, f2 = sys.argv[1:5]

def load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path,"r",encoding="utf-8") as f:
        return json.load(f)

def save_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path,"w",encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)

def norm_unified(j):
    # return (container_type, items, container_obj)
    if isinstance(j, list):
        return ("list", j, None)
    if isinstance(j, dict):
        if isinstance(j.get("items"), list):
            return ("dict_items", j["items"], j)
        if isinstance(j.get("findings"), list):
            return ("dict_findings", j["findings"], j)
        # unknown dict -> treat as container with items
        j.setdefault("items", [])
        if not isinstance(j["items"], list): j["items"]=[]
        return ("dict_items", j["items"], j)
    return ("list", [], None)

def gitleaks_to_items(gl):
    # gitleaks.json usually is list of findings
    if isinstance(gl, dict) and isinstance(gl.get("findings"), list):
        rows = gl["findings"]
    elif isinstance(gl, list):
        rows = gl
    else:
        rows = []

    out=[]
    for r in rows:
        if not isinstance(r, dict): 
            continue
        file = r.get("File") or r.get("file") or r.get("Path") or ""
        line = r.get("StartLine") or r.get("start_line") or r.get("Line") or r.get("line") or ""
        rule = r.get("RuleID") or r.get("rule") or r.get("Rule") or r.get("Description") or "gitleaks"
        desc = r.get("Description") or r.get("description") or ""
        # avoid leaking secret in title
        title = (desc.strip() or str(rule)).strip()
        if len(title) > 180: title = title[:180] + "…"

        fp_src = f"gitleaks|{file}|{line}|{rule}|{title}"
        fp = hashlib.sha1(fp_src.encode("utf-8", errors="ignore")).hexdigest()

        it = {
            "tool": "gitleaks",
            "severity": "HIGH",                 # commercial default; later can refine by ruleset
            "cwe": "CWE-798",                   # Hard-coded credentials
            "title": title,
            "file": file,
            "line": line,
            "rule": rule,
            "fingerprint": fp,
            "ts": datetime.datetime.utcnow().isoformat()+"Z",
            "raw": {                            # keep raw but DO NOT include Secret field if present
                k:v for k,v in r.items() if k.lower() not in ("secret","match")
            }
        }
        out.append(it)
    return out

gl = load_json(gl_path, [])
new_items = gitleaks_to_items(gl)
print("[INFO] gitleaks_items:", len(new_items))

# Load unified from root (prefer root; fallback reports)
unified = load_json(f1, None)
if unified is None:
    unified = load_json(f2, [])
ctype, items, container = norm_unified(unified)

# de-dup by fingerprint
seen=set()
for it in items:
    if isinstance(it, dict):
        fp = it.get("fingerprint") or it.get("hash") or ""
        if fp: seen.add(fp)

added=0
for it in new_items:
    if it["fingerprint"] in seen: 
        continue
    items.append(it)
    seen.add(it["fingerprint"])
    added += 1

print("[OK] added:", added, "total_now:", len(items))

# Write back in same outer format
if ctype == "list":
    save_json(f1, items)
else:
    container["items"] = items
    container["total"] = len(items)
    save_json(f1, container)

# mirror to reports if exists
if os.path.isdir(os.path.join(ci, "reports")):
    try:
        if ctype == "list":
            save_json(f2, items)
        else:
            save_json(f2, container)
        print("[OK] mirrored to reports/findings_unified.json")
    except Exception as e:
        print("[WARN] mirror failed:", e)
PY

echo "== verify API =="
RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -er '.items[0].run_id')"
curl -sS "http://127.0.0.1:8910/api/vsp/findings_preview_v1/${RID}?limit=3" | jq '{ok,total,items_n,file}'
