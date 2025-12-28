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
  name="$(echo "$p" | tr '/' '_')"   # /vsp5 -> _vsp5
  fn="$OUT/${name}.html"
  echo "== FETCH $p =="
  curl -fsS "$BASE$p" -o "$fn"
  echo "saved => $fn"
done

echo
echo "== DEBUG ls OUT =="
ls -lah "$OUT" | sed -n '1,40p'

export OUT
python3 - <<'PY'
import os, re, json, collections
from pathlib import Path

out = Path(os.environ["OUT"])
print(f"\n== DOM CONTRACT AUDIT in {out} ==")

html_files = sorted(out.glob("*.html"))
if not html_files:
    raise SystemExit(f"[ERR] no html files in {out}")

need_ids = {"_vsp5.html": ["vsp-dashboard-main"]}

def find_ids(html: str):
    return re.findall(r"""\bid\s*=\s*["']([^"']+)["']""", html)

def find_assets(html: str):
    return re.findall(r"""(?:src|href)\s*=\s*["']([^"']*(?:static/(?:js|css)/)[^"']+)["']""", html)

def has_template_leak(html: str):
    return ("{{" in html) or ("{%" in html)

report = {}
any_dup = False
any_tmpl = False

for path in html_files:
    fn = path.name  # e.g. _vsp5.html
    html = path.read_text(encoding="utf-8", errors="replace")

    ids = find_ids(html)
    c = collections.Counter(ids)
    dups = [k for k,v in c.items() if v > 1]
    assets = find_assets(html)
    tmpl = has_template_leak(html)

    must = need_ids.get(fn, [])
    missing = [x for x in must if x not in c]

    report[fn] = {
        "ids_total": len(ids),
        "dup_ids": dups[:80],
        "missing_required_ids": missing,
        "assets": assets[:400],
        "template_leak": tmpl,
    }

    any_dup = any_dup or bool(dups)
    any_tmpl = any_tmpl or tmpl

print("\n== REQUIRED IDs ==")
for fn, req in need_ids.items():
    if fn not in report:
        print("[FAIL]", fn, "file missing in OUT")
        continue
    miss = report[fn]["missing_required_ids"]
    print(("[FAIL]" if miss else "[OK]  "), fn, "missing="+str(miss) if miss else "has="+str(req))

print("\n== DUPLICATE IDs (bad) ==")
if any_dup:
    for fn, r in report.items():
        if r["dup_ids"]:
            print(f"[FAIL] {fn} dup_id_count={len(r['dup_ids'])} sample={r['dup_ids'][:12]}")
else:
    print("[OK] no duplicate ids found")

print("\n== TEMPLATE LEAK CHECK ({{ or {%}) ==")
if any_tmpl:
    for fn, r in report.items():
        if r["template_leak"]:
            print(f"[WARN] {fn} contains template markers")
else:
    print("[OK] no obvious template leak markers")

(out / "dom_contract_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"\n[OK] wrote: {out/'dom_contract_report.json'}")
PY

echo
echo "== OPEN REPORT =="
echo "cat $OUT/dom_contract_report.json | python3 -m json.tool | less"
