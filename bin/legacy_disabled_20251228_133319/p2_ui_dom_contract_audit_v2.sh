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
  fn="${OUT}$(echo "$p" | tr '/' '_').html"
  echo "== FETCH $p =="
  curl -fsS "$BASE$p" -o "$fn"
  echo "saved => $fn"
done

export OUT
python3 - <<'PY'
import os, re, json, collections
from pathlib import Path

out = Path(os.environ["OUT"])
print(f"\n== DOM CONTRACT AUDIT in {out} ==")

# map actual filenames we saved
files = {
  "_vsp5.html": out / "_vsp5.html",
  "_runs.html": out / "_runs.html",
  "_data_source.html": out / "_data_source.html",
  "_settings.html": out / "_settings.html",
  "_rule_overrides.html": out / "_rule_overrides.html",
}

need_ids = {"_vsp5.html":["vsp-dashboard-main"]}

def find_ids(html: str):
    return re.findall(r"""\bid\s*=\s*["']([^"']+)["']""", html)

def find_assets(html: str):
    return re.findall(r"""(?:src|href)\s*=\s*["']([^"']*(?:static/(?:js|css)/)[^"']+)["']""", html)

def has_template_leak(html: str):
    return ("{{" in html) or ("{%" in html)

all_report = {}

for fn, path in files.items():
    html = path.read_text(encoding="utf-8", errors="replace")
    ids = find_ids(html)
    c = collections.Counter(ids)
    dups = [k for k,v in c.items() if v > 1]
    assets = find_assets(html)
    tmpl = has_template_leak(html)

    must = need_ids.get(fn, [])
    missing = [x for x in must if x not in c]

    all_report[fn] = {
        "ids_total": len(ids),
        "dup_ids": dups[:80],
        "missing_required_ids": missing,
        "assets": assets[:400],
        "template_leak": tmpl,
    }

print("\n== REQUIRED IDs ==")
for fn, req in need_ids.items():
    miss = all_report[fn]["missing_required_ids"]
    print(("[FAIL]" if miss else "[OK]  "), fn, "missing=" + str(miss) if miss else "has=" + str(req))

print("\n== DUPLICATE IDs (bad) ==")
any_dup = False
for fn, r in all_report.items():
    if r["dup_ids"]:
        any_dup = True
        print(f"[FAIL] {fn} dup_id_count={len(r['dup_ids'])} sample={r['dup_ids'][:12]}")
if not any_dup:
    print("[OK] no duplicate ids found")

print("\n== TEMPLATE LEAK CHECK ({{ or {%}) ==")
any_tmpl = False
for fn, r in all_report.items():
    if r["template_leak"]:
        any_tmpl = True
        print(f"[WARN] {fn} contains template markers (possible leak)")
if not any_tmpl:
    print("[OK] no obvious template leak markers")

(out / "dom_contract_report.json").write_text(json.dumps(all_report, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"\n[OK] wrote: {out/'dom_contract_report.json'}")
PY

echo
echo "== OPEN REPORT =="
echo "cat $OUT/dom_contract_report.json | python3 -m json.tool | less"
