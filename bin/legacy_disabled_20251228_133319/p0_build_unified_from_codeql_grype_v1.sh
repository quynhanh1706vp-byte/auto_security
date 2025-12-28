#!/usr/bin/env bash
set -euo pipefail

RUN="/home/test/Data/SECURITY_BUNDLE/out/VSP_CI_20251219_092640"
RID_ALIAS="VSP_CI_RUN_20251219_092640"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

# cap để UI nhẹ (tùy bạn)
MAX_ITEMS="${MAX_ITEMS:-2500}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need jq; need mkdir; need curl

[ -d "$RUN" ] || { echo "[ERR] missing run dir: $RUN"; exit 2; }
mkdir -p "$RUN/reports"

python3 - <<PY
import json, os, csv, hashlib, datetime
from pathlib import Path

run = Path("${RUN}")
max_items = int(os.environ.get("MAX_ITEMS","${MAX_ITEMS}"))

def norm_sev(s):
    s = (s or "").strip().upper()
    if s in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"):
        return s
    # map common
    if s in ("ERROR",): return "HIGH"
    if s in ("WARNING","WARN"): return "MEDIUM"
    if s in ("NOTE",): return "LOW"
    if s in ("NONE",): return "INFO"
    return "INFO"

def mk_id(*parts):
    h = hashlib.sha1(("|".join([p or "" for p in parts])).encode("utf-8","replace")).hexdigest()[:16]
    return h

items = []
counts = {k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}

def push(item):
    sev = item.get("severity","INFO")
    sev = norm_sev(sev)
    item["severity"] = sev
    counts[sev] = counts.get(sev,0)+1
    items.append(item)

# ---- GRYPE ----
grype = run/"grype/grype.json"
if grype.is_file():
    try:
        g = json.loads(grype.read_text(encoding="utf-8", errors="replace"))
        for m in (g.get("matches") or []):
            if len(items) >= max_items: break
            vuln = (m.get("vulnerability") or {})
            art  = (m.get("artifact") or {})
            pkg  = (art.get("name") or art.get("purl") or "")
            ver  = (art.get("version") or "")
            vid  = (vuln.get("id") or vuln.get("vulnerabilityID") or "")
            sev  = (vuln.get("severity") or "INFO")
            desc = (vuln.get("description") or "")
            fix  = (vuln.get("fix") or {}).get("versions") if isinstance(vuln.get("fix"), dict) else None
            fix_s = ",".join(fix) if isinstance(fix, list) else ""
            title = f"{vid} in {pkg} {ver}".strip()
            push({
                "id": mk_id("grype", vid, pkg, ver),
                "tool": "grype",
                "type": "SCA",
                "title": title[:200],
                "severity": sev,
                "component": pkg,
                "version": ver,
                "location": (m.get("artifact") or {}).get("purl","") or "",
                "description": (desc or "")[:400],
                "fix": fix_s[:200],
            })
    except Exception as e:
        push({
            "id": mk_id("grype","parse_error"),
            "tool":"grype",
            "type":"SYSTEM",
            "title":"grype.json parse error",
            "severity":"INFO",
            "description": str(e)[:400],
        })

# ---- CODEQL SARIF ----
def sarif_level_to_sev(level, secsev=None):
    # CodeQL/SARIF level mapping
    level = (level or "").lower()
    # if CodeQL security-severity exists (0-10 as str), use it to bump
    try:
        f = float(secsev) if secsev is not None else None
    except Exception:
        f = None
    if f is not None:
        if f >= 9: return "CRITICAL"
        if f >= 7: return "HIGH"
        if f >= 4: return "MEDIUM"
        if f >= 1: return "LOW"
        return "INFO"
    if level == "error": return "HIGH"
    if level == "warning": return "MEDIUM"
    if level == "note": return "LOW"
    return "INFO"

for sar in sorted((run/"codeql").glob("*.sarif")):
    if not sar.is_file(): continue
    if len(items) >= max_items: break
    try:
        s = json.loads(sar.read_text(encoding="utf-8", errors="replace"))
        for run0 in (s.get("runs") or []):
            rules = {}
            try:
                for r in ((run0.get("tool") or {}).get("driver") or {}).get("rules") or []:
                    if isinstance(r, dict) and r.get("id"):
                        rules[r["id"]] = r
            except Exception:
                pass

            for res in (run0.get("results") or []):
                if len(items) >= max_items: break
                rid = res.get("ruleId") or ""
                lvl = res.get("level") or ""
                rule = rules.get(rid, {})
                # CodeQL sometimes stores security-severity here:
                secsev = None
                props = rule.get("properties") if isinstance(rule, dict) else None
                if isinstance(props, dict):
                    secsev = props.get("security-severity") or props.get("securitySeverity")
                sev = sarif_level_to_sev(lvl, secsev)

                msg = (res.get("message") or {}).get("text") if isinstance(res.get("message"), dict) else str(res.get("message") or "")
                msg = (msg or "").strip()
                title = msg.splitlines()[0][:200] if msg else (rid[:200] or "CodeQL finding")

                loc_path = ""
                loc_line = ""
                try:
                    locs = res.get("locations") or []
                    if locs:
                        phys = (locs[0].get("physicalLocation") or {})
                        art = (phys.get("artifactLocation") or {})
                        loc_path = art.get("uri") or ""
                        reg = (phys.get("region") or {})
                        loc_line = str(reg.get("startLine") or "")
                except Exception:
                    pass

                push({
                    "id": mk_id("codeql", sar.name, rid, loc_path, loc_line, title),
                    "tool": "codeql",
                    "type": "SAST",
                    "rule_id": rid,
                    "title": title,
                    "severity": sev,
                    "location": f"{loc_path}:{loc_line}".strip(":"),
                    "description": msg[:400],
                })
    except Exception as e:
        push({
            "id": mk_id("codeql", sar.name, "parse_error"),
            "tool":"codeql",
            "type":"SYSTEM",
            "title": f"{sar.name} parse error",
            "severity":"INFO",
            "description": str(e)[:400],
        })

# Build unified objects
meta = {
    "ok": True,
    "run_id": run.name,
    "generated_at": datetime.datetime.utcnow().isoformat() + "Z",
    "max_items": max_items,
    "counts_by_severity": counts,
    "items_total": len(items),
    "sources": {
        "grype": str(grype) if grype.is_file() else None,
        "codeql": [str(p) for p in sorted((run/'codeql').glob('*.sarif'))],
    }
}

unified = {
    "meta": meta,
    "findings": items,   # keep key name "findings" explicit
}

# Write JSON (both root + reports, to satisfy any resolver)
(root_json, rep_json) = (run/"findings_unified.json", run/"reports/findings_unified.json")
root_json.write_text(json.dumps(unified, ensure_ascii=False, indent=2), encoding="utf-8")
rep_json.write_text(json.dumps(unified, ensure_ascii=False, indent=2), encoding="utf-8")

# Also write "commercial" variant for compatibility
(run/"findings_unified_commercial.json").write_text(json.dumps(unified, ensure_ascii=False, indent=2), encoding="utf-8")
(run/"reports/findings_unified_commercial.json").write_text(json.dumps(unified, ensure_ascii=False, indent=2), encoding="utf-8")

# Write CSV into reports + root
csv_fields = ["id","tool","type","severity","title","rule_id","component","version","location","fix"]
def write_csv(p: Path):
    with p.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=csv_fields)
        w.writeheader()
        for it in items:
            w.writerow({k: (it.get(k,"") or "") for k in csv_fields})

write_csv(run/"reports/findings_unified.csv")
write_csv(run/"findings_unified.csv")

print("[OK] wrote unified:")
print(" -", rep_json)
print(" -", run/"reports/findings_unified.csv")
print("[OK] items:", len(items))
print("[OK] counts:", counts)
PY

echo "[INFO] verify export_csv size after build (expect > 47)"
curl -sS -I "${BASE}/api/vsp/export_csv?rid=${RID_ALIAS}" | egrep -i 'HTTP/|Content-Length|Content-Disposition' || true

echo "[INFO] verify Data Source JSON quick peek (first 2 findings)"
curl -sS "${BASE}/api/vsp/run_file?rid=${RID_ALIAS}&name=reports/findings_unified.json" | jq -r '.meta.items_total, (.findings[0].tool + " " + .findings[0].severity + " " + .findings[0].title), (.findings[1].tool + " " + .findings[1].severity + " " + .findings[1].title)' 2>/dev/null || true
