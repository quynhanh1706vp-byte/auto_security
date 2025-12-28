#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/vsp_ui_dom_audit_${TS}"
mkdir -p "$OUT"

pages=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "OUT=$OUT"
echo

for p in "${pages[@]}"; do
  echo "== FETCH $p =="
  curl -fsS "$BASE$p" -o "$OUT$(echo "$p" | tr '/' '_').html"
  echo "saved => $OUT$(echo "$p" | tr '/' '_').html"
done

python3 - <<'PY'
from pathlib import Path
import re, json, collections

out = Path("/tmp").glob("vsp_ui_dom_audit_*")
out = max(out, key=lambda p: p.stat().st_mtime)
print(f"\n== DOM CONTRACT AUDIT in {out} ==")

pages = ["_vsp5.html","_runs.html","_data_source.html","_settings.html","_rule_overrides.html"]
need_ids = {"_vsp5.html":["vsp-dashboard-main"]}

def find_ids(html: str):
    # capture id="..." and id='...'
    return re.findall(r"""\bid\s*=\s*["']([^"']+)["']""", html)

def find_assets(html: str):
    # capture static/js/... and static/css/...
    return re.findall(r"""(?:src|href)\s*=\s*["']([^"']*(?:static/(?:js|css)/)[^"']+)["']""", html)

def has_template_leak(html: str):
    return ("{{" in html) or ("{%" in html)

all_report = {}
dup_any = False
tmpl_any = False

for fn in pages:
    p = out / fn
    html = p.read_text(encoding="utf-8", errors="replace")
    ids = find_ids(html)
    c = collections.Counter(ids)
    dups = [k for k,v in c.items() if v > 1]
    assets = find_assets(html)
    tmpl = has_template_leak(html)

    if dups: dup_any = True
    if tmpl: tmpl_any = True

    must = need_ids.get(fn, [])
    missing = [x for x in must if x not in c]

    all_report[fn] = {
        "ids_total": len(ids),
        "dup_ids": dups[:50],
        "missing_required_ids": missing,
        "assets": assets[:200],
        "template_leak": tmpl,
    }

print("\n== REQUIRED IDs ==")
for fn,req in need_ids.items():
    miss = all_report[fn]["missing_required_ids"]
    if miss:
        print(f"[FAIL] {fn} missing required ids: {miss}")
    else:
        print(f"[OK]   {fn} has required ids: {req}")

print("\n== DUPLICATE IDs (bad) ==")
for fn,r in all_report.items():
    if r["dup_ids"]:
        print(f"[FAIL] {fn} dup id count={len(r['dup_ids'])} sample={r['dup_ids'][:10]}")
if not any(all_report[fn]["dup_ids"] for fn in pages):
    print("[OK] no duplicate ids found")

print("\n== TEMPLATE LEAK CHECK ({{ or {%}) ==")
for fn,r in all_report.items():
    if r["template_leak"]:
        print(f"[WARN] {fn} contains template markers (possible leak): '{{' or '{{%'}}")
if not any(all_report[fn]["template_leak"] for fn in pages):
    print("[OK] no obvious template leak markers")

# dump machine-readable report
(out / "dom_contract_report.json").write_text(json.dumps(all_report, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"\n[OK] wrote: {out/'dom_contract_report.json'}")
PY

echo
echo "== TIP: open report =="
echo "cat $OUT/dom_contract_report.json | python3 -m json.tool | less"
