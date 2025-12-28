#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56h3_loaded_js_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need node; need sort; need uniq; need wc; need head

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== [P56H3 v2 FIX] Loaded-JS syntax gate ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"

# 1) fetch HTML per tab
for p in "${tabs[@]}"; do
  f="$EVID/$(echo "$p" | tr '/?' '__').html"
  code="000"
  for i in 1 2 3; do
    code="$(curl -sS --connect-timeout 2 -m 8 -o "$f" -w "%{http_code}" "$BASE$p" || true)"
    [ "$code" != "000" ] && break
    sleep 0.3
  done
  echo "[HTTP] $p => $code" | tee -a "$EVID/summary.txt"
done

# 2) extract loaded JS from HTML (python file, no heredoc risk)
cat > "$EVID/extract_loaded_js.py" <<'PY'
from pathlib import Path
import re, json

evid = Path(__file__).resolve().parent
js=set()

for html in evid.glob("*.html"):
    s=html.read_text(encoding="utf-8", errors="replace")
    for m in re.finditer(r'src="(/static/js/[^"]+\.js[^"]*)"', s):
        u=m.group(1).split("#",1)[0]
        js.add(u)

urls = sorted(js)
(evid/"loaded_js_urls.txt").write_text("\n".join(urls)+("\n" if urls else ""), encoding="utf-8")

files=[]
for u in urls:
    path=u.split("?",1)[0]
    path=path[len("/static/"):] if path.startswith("/static/") else path
    files.append("static/"+path)

files=sorted(set(files))
(evid/"loaded_js_files.txt").write_text("\n".join(files)+("\n" if files else ""), encoding="utf-8")

j={"loaded_js_urls":len(urls), "loaded_js_files":len(files)}
(evid/"loaded_counts.json").write_text(json.dumps(j, indent=2), encoding="utf-8")
print(json.dumps(j))
PY

python3 "$EVID/extract_loaded_js.py" | tee -a "$EVID/summary.txt"

# 3) node --check only loaded files
: > "$EVID/fails.txt"
okc=0; failc=0
while read -r f; do
  [ -n "${f:-}" ] || continue
  if [ ! -f "$f" ]; then
    echo "[WARN] missing file: $f" | tee -a "$EVID/summary.txt"
    continue
  fi
  if node --check "$f" >/dev/null 2>"$EVID/$(basename "$f").nodecheck.err"; then
    okc=$((okc+1))
  else
    echo "[FAIL] syntax: $f" | tee -a "$EVID/summary.txt"
    echo "$f" >> "$EVID/fails.txt"
    failc=$((failc+1))
  fi
done < "$EVID/loaded_js_files.txt"

echo "[OK] syntax_ok=$okc syntax_fail=$failc" | tee -a "$EVID/summary.txt"

# 4) optional compare with latest P56G
latest_p56g="$(ls -1dt out_ci/p56g_js_syntax_* 2>/dev/null | head -n 1 || true)"
if [ -n "${latest_p56g:-}" ] && [ -f "$latest_p56g/fails.txt" ]; then
  echo "[INFO] latest_p56g=$latest_p56g" | tee -a "$EVID/summary.txt"
  grep -Fx -f "$latest_p56g/fails.txt" "$EVID/loaded_js_files.txt" > "$EVID/loaded_intersect_p56g.txt" || true
  echo "[OK] loaded∩p56g_fails=$(wc -l < "$EVID/loaded_intersect_p56g.txt")" | tee -a "$EVID/summary.txt"
fi

# 5) verdict (python file; NO heredoc pipe)
cat > "$EVID/write_verdict.py" <<'PY'
import json, datetime, pathlib
e=pathlib.Path(__file__).resolve().parent
fails = e/"fails.txt"
fail_lines = []
if fails.exists():
    t=fails.read_text(encoding="utf-8", errors="replace").strip()
    fail_lines = [x for x in t.splitlines() if x.strip()] if t else []

j={
  "ok": (len(fail_lines)==0),
  "ts": datetime.datetime.now().isoformat(),
  "base": str((e/".."/"..").resolve()),
  "evidence_dir": str(e),
  "fails_count": len(fail_lines),
}
(e/"verdict.json").write_text(json.dumps(j, indent=2), encoding="utf-8")
print(json.dumps(j, indent=2))
PY

python3 "$EVID/write_verdict.py" | tee -a "$EVID/summary.txt"

if [ -s "$EVID/fails.txt" ]; then
  echo "[DONE] P56H3 FAIL. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 1
fi
echo "[DONE] P56H3 PASS. Evidence=$EVID" | tee -a "$EVID/summary.txt"
