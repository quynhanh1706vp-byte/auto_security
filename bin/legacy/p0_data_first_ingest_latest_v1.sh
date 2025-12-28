#!/usr/bin/env bash
set -euo pipefail

# CONFIG
SRC_ROOT="/home/test/Data/SECURITY-10-10-v4/out_ci"
DST_ROOT="/home/test/Data/SECURITY_BUNDLE/out"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
MAX_ITEMS="${MAX_ITEMS:-2500}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need ls; need head; need basename; need rsync; need mkdir; need ln; need cp; need python3; need curl; need jq; need date

mkdir -p "$DST_ROOT"

SRC="$(ls -1dt "$SRC_ROOT"/VSP_CI_* 2>/dev/null | head -n1 || true)"
[ -n "$SRC" ] || { echo "[ERR] no source VSP_CI_* in $SRC_ROOT"; exit 2; }
RID_SRC="$(basename "$SRC")"

DST="$DST_ROOT/$RID_SRC"
rsync -a --delete "$SRC/" "$DST/"
echo "[OK] imported: $RID_SRC"

ALIAS="VSP_CI_RUN_${RID_SRC#VSP_CI_}"
ALIAS_PATH="$DST_ROOT/$ALIAS"
rm -f "$ALIAS_PATH" || true
ln -s "$RID_SRC" "$ALIAS_PATH"
echo "[OK] alias: $ALIAS_PATH -> $RID_SRC"

mkdir -p "$DST/reports"
if [ -f "$DST/run_gate_summary.json" ] && [ ! -f "$DST/reports/run_gate_summary.json" ]; then
  cp -f "$DST/run_gate_summary.json" "$DST/reports/run_gate_summary.json"
fi

# build unified from grype+codeql (same logic as your v1; embedded minimal)

# --- VSP_P0_INGEST_GUARD_FORCE_V1 ---
FORCE="${FORCE:-0}"
if [ "${FORCE}" != "1" ] && [ -f "$DST/reports/findings_unified.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    GEN="$(jq -r '.meta.generated_at // empty' "$DST/reports/findings_unified.json" 2>/dev/null || true)"
    TOT="$(jq -r '.meta.items_total // empty' "$DST/reports/findings_unified.json" 2>/dev/null || true)"
    if [ -n "$GEN" ] && [ -n "$TOT" ]; then
      echo "[SKIP] unified already built (generated_at=$GEN items_total=$TOT). Set FORCE=1 to rebuild."
      echo "[INFO] verify export_csv size for rid=$ALIAS"
      curl -sS -I "$BASE/api/vsp/export_csv?rid=$ALIAS" | egrep -i 'HTTP/|Content-Length|Content-Disposition' || true
      exit 0
    fi
  fi
fi
# --- /VSP_P0_INGEST_GUARD_FORCE_V1 ---

python3 - <<PY
import json, os, csv, hashlib, datetime
from pathlib import Path
run=Path("${DST}")
max_items=int(os.environ.get("MAX_ITEMS","${MAX_ITEMS}"))

def mk_id(*parts):
    import hashlib
    h=hashlib.sha1(("|".join([p or "" for p in parts])).encode("utf-8","replace")).hexdigest()[:16]
    return h

def norm_sev(s):
    s=(s or "").strip().upper()
    if s in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"): return s
    if s in ("ERROR",): return "HIGH"
    if s in ("WARNING","WARN"): return "MEDIUM"
    if s in ("NOTE",): return "LOW"
    return "INFO"

def sarif_level_to_sev(level, secsev=None):
    level=(level or "").lower()
    try:
        f=float(secsev) if secsev is not None else None
    except Exception:
        f=None
    if f is not None:
        if f>=9: return "CRITICAL"
        if f>=7: return "HIGH"
        if f>=4: return "MEDIUM"
        if f>=1: return "LOW"
        return "INFO"
    if level=="error": return "HIGH"
    if level=="warning": return "MEDIUM"
    if level=="note": return "LOW"
    return "INFO"

items=[]
counts={k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}
def push(it):
    it["severity"]=norm_sev(it.get("severity","INFO"))
    counts[it["severity"]]+=1
    items.append(it)

# grype
gpath=run/"grype/grype.json"
if gpath.is_file():
    g=json.loads(gpath.read_text(encoding="utf-8", errors="replace"))
    for m in (g.get("matches") or []):
        if len(items)>=max_items: break
        vuln=m.get("vulnerability") or {}
        art=m.get("artifact") or {}
        pkg=art.get("name") or art.get("purl") or ""
        ver=art.get("version") or ""
        vid=vuln.get("id") or vuln.get("vulnerabilityID") or ""
        sev=vuln.get("severity") or "INFO"
        desc=vuln.get("description") or ""
        title=f"{vid} in {pkg} {ver}".strip()
        push({
          "id": mk_id("grype", vid, pkg, ver),
          "tool":"grype","type":"SCA",
          "title": title[:200],
          "severity": sev,
          "component": pkg,
          "version": ver,
          "location": art.get("purl","") or "",
          "description": desc[:400],
          "fix":""
        })

# codeql sarif
for sar in sorted((run/"codeql").glob("*.sarif")):
    if len(items)>=max_items: break
    s=json.loads(sar.read_text(encoding="utf-8", errors="replace"))
    for run0 in (s.get("runs") or []):
        rules={}
        for r in (((run0.get("tool") or {}).get("driver") or {}).get("rules") or []):
            if isinstance(r, dict) and r.get("id"): rules[r["id"]]=r
        for res in (run0.get("results") or []):
            if len(items)>=max_items: break
            rid=res.get("ruleId") or ""
            lvl=res.get("level") or ""
            rule=rules.get(rid, {})
            props=rule.get("properties") if isinstance(rule, dict) else None
            secsev=props.get("security-severity") if isinstance(props, dict) else None
            sev=sarif_level_to_sev(lvl, secsev)
            msg=(res.get("message") or {}).get("text") if isinstance(res.get("message"), dict) else str(res.get("message") or "")
            msg=(msg or "").strip()
            title=(msg.splitlines()[0] if msg else (rid or "CodeQL finding"))[:200]
            loc=""
            try:
                locs=res.get("locations") or []
                if locs:
                    phys=locs[0].get("physicalLocation") or {}
                    art=phys.get("artifactLocation") or {}
                    uri=art.get("uri") or ""
                    reg=phys.get("region") or {}
                    ln=str(reg.get("startLine") or "")
                    loc=f"{uri}:{ln}".strip(":")
            except Exception:
                pass
            push({
              "id": mk_id("codeql", sar.name, rid, loc, title),
              "tool":"codeql","type":"SAST",
              "rule_id": rid,
              "title": title,
              "severity": sev,
              "location": loc,
              "description": msg[:400],
            })

meta={
  "ok": True,
  "run_id": run.name,
  "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "max_items": max_items,
  "counts_by_severity": counts,
  "items_total": len(items),
  "sources": {
    "grype": str(gpath) if gpath.is_file() else None,
    "codeql": [str(p) for p in sorted((run/'codeql').glob('*.sarif'))],
  }
}
unified={"meta": meta, "findings": items}

(run/"findings_unified.json").write_text(json.dumps(unified, ensure_ascii=False, indent=2), encoding="utf-8")
(run/"findings_unified_commercial.json").write_text(json.dumps(unified, ensure_ascii=False, indent=2), encoding="utf-8")
(run/"reports/findings_unified.json").write_text(json.dumps(unified, ensure_ascii=False, indent=2), encoding="utf-8")
(run/"reports/findings_unified_commercial.json").write_text(json.dumps(unified, ensure_ascii=False, indent=2), encoding="utf-8")

fields=["id","tool","type","severity","title","rule_id","component","version","location","fix"]
def write_csv(p):
    with open(p,"w",encoding="utf-8",newline="") as f:
        w=csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for it in items:
            w.writerow({k:(it.get(k,"") or "") for k in fields})

write_csv(run/"findings_unified.csv")
write_csv(run/"reports/findings_unified.csv")
print("[OK] built unified items:", len(items), "counts:", counts)
PY

echo "[INFO] verify export_csv size for rid=$ALIAS"
curl -sS -I "$BASE/api/vsp/export_csv?rid=$ALIAS" | egrep -i 'HTTP/|Content-Length|Content-Disposition' || true
