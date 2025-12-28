#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p57_ui_luxe_gate_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need node; need python3; need sed; need awk; need sort; need uniq; need head; need wc

echo "== [P57] UI LUXE gate (headless) ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

# A) HTTP reachability (retry)
for p in "${tabs[@]}"; do
  code="000"
  for i in 1 2 3 4 5; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 4 "$BASE$p" || true)"
    echo "[HTTP] $p try#$i => $code" | tee -a "$EVID/summary.txt"
    [ "$code" = "200" ] && break
    sleep 0.4
  done
  if [ "$code" != "200" ]; then
    echo "[FAIL] tab not 200: $p" | tee -a "$EVID/summary.txt"
    exit 1
  fi
done

# B) extract LOADED JS (what browser actually loads)
: > "$EVID/loaded_js_urls.txt"
for p in "${tabs[@]}"; do
  curl -fsS --connect-timeout 1 --max-time 8 "$BASE$p" \
    | sed -n 's/.*<script[^>]*src="\([^"]\+\)".*/\1/p' \
    | sed 's/&amp;/\&/g' \
    >> "$EVID/loaded_js_urls.txt" || true
done

cat "$EVID/loaded_js_urls.txt" \
  | awk 'BEGIN{FS="\\?"; OFS=""}{print $1}' \
  | awk '
      $0 ~ /^https?:\/\// {next}
      $0 ~ /^\// {print $0; next}
      {print "/" $0}
    ' \
  | sort -u \
  > "$EVID/loaded_js_urls_uniq.txt"

python3 - <<'PY'
from pathlib import Path
import json

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
evid = root / "out_ci"
# find latest P57 evidence dir by name (this script created it)
# we can rely on env passed via file read:
# Just locate newest p57 directory and use it.
dirs = sorted((root/"out_ci").glob("p57_ui_luxe_gate_*"), key=lambda p: p.stat().st_mtime, reverse=True)
assert dirs, "no p57 evidence dir found"
E = dirs[0]

urls = (E/"loaded_js_urls_uniq.txt").read_text(encoding="utf-8", errors="replace").splitlines()
files=[]
for u in urls:
    u=u.strip()
    if not u: 
        continue
    if u.startswith("/static/"):
        rel = u.lstrip("/")  # static/...
        f = root / rel
        if f.exists():
            files.append(str(f.relative_to(root)))
    elif u.startswith("/"):
        # ignore non-static paths
        pass

files = sorted(set(files))
(E/"loaded_js_files.txt").write_text("\n".join(files)+"\n", encoding="utf-8")
(E/"loaded_js_meta.json").write_text(json.dumps({
    "loaded_js_urls": len(urls),
    "loaded_js_files": len(files),
}, ensure_ascii=False), encoding="utf-8")
print(json.dumps({"loaded_js_urls": len(urls), "loaded_js_files": len(files)}))
PY | tee -a "$EVID/summary.txt"

# C) node --check ONLY on loaded JS (strict)
ok=1
: > "$EVID/js_syntax_fails.txt"
while IFS= read -r rel; do
  [ -z "${rel:-}" ] && continue
  if ! node --check "$rel" >/dev/null 2>"$EVID/_node_err.tmp"; then
    ok=0
    echo "[FAIL] $rel" | tee -a "$EVID/summary.txt"
    echo "== $rel ==" >> "$EVID/js_syntax_fails.txt"
    cat "$EVID/_node_err.tmp" >> "$EVID/js_syntax_fails.txt"
    echo >> "$EVID/js_syntax_fails.txt"
  fi
done < "$EVID/loaded_js_files.txt"
rm -f "$EVID/_node_err.tmp" || true

if [ "$ok" != "1" ]; then
  echo "[FAIL] loaded-js has syntax errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 1
fi
echo "[OK] loaded-js syntax OK" | tee -a "$EVID/summary.txt"

# D) Playwright runtime gate (REAL): console/pageerror + html + screenshot
# Must run from UI folder so node can resolve ./node_modules/playwright
if ! node -e 'require("playwright"); console.log("playwright_ok")' >/dev/null 2>&1; then
  echo "[FAIL] Playwright not installed in UI folder." | tee -a "$EVID/summary.txt"
  echo "       Install: cd /home/test/Data/SECURITY_BUNDLE/ui && npm i -D playwright && npx playwright install chromium" | tee -a "$EVID/summary.txt"
  exit 2
fi

cat > "$EVID/pw_gate.js" <<'JS'
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const BASE = process.env.BASE || "http://127.0.0.1:8910";
const EVID = process.env.EVID || ".";
const tabs = ["/vsp5","/runs","/data_source","/settings","/rule_overrides"];

function jline(file, obj){
  fs.appendFileSync(path.join(EVID, file), JSON.stringify(obj) + "\n", "utf-8");
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  page.on("console", (msg) => {
    const type = msg.type();
    const text = msg.text();
    jline("console.jsonl", { ts: new Date().toISOString(), type, text });
  });

  page.on("pageerror", (err) => {
    jline("pageerror.jsonl", { ts: new Date().toISOString(), message: String(err && err.message || err), stack: String(err && err.stack || "") });
  });

  page.on("requestfailed", (req) => {
    jline("requestfailed.jsonl", { ts: new Date().toISOString(), url: req.url(), failure: req.failure() });
  });

  for (const p of tabs) {
    const url = BASE + p;
    const started = Date.now();
    try{
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 25000 });
      // basic contract: top tabs text should exist somewhere
      const must = ["Dashboard","Runs","Data Source","Settings","Rule Overrides"];
      const bodyText = await page.textContent("body");
      let miss = [];
      for (const t of must) if (!bodyText || !bodyText.includes(t)) miss.push(t);
      if (miss.length) {
        jline("contract_fail.jsonl", { ts: new Date().toISOString(), url, missing: miss });
      }

      // snapshot HTML
      const html = await page.content();
      fs.writeFileSync(path.join(EVID, `page_${p.replace(/\W+/g,"_")}.html`), html, "utf-8");

      // screenshot (don’t let it block forever)
      try{
        await page.screenshot({ path: path.join(EVID, `page_${p.replace(/\W+/g,"_")}.png`), fullPage: true, timeout: 12000 });
      } catch(e){
        jline("screenshot_fail.jsonl", { ts: new Date().toISOString(), url, err: String(e && e.message || e) });
      }

      jline("nav_ok.jsonl", { ts: new Date().toISOString(), url, ms: Date.now()-started });
    }catch(e){
      jline("nav_fail.jsonl", { ts: new Date().toISOString(), url, err: String(e && e.message || e) });
    }
  }

  await browser.close();
})();
JS

export BASE EVID
node "$EVID/pw_gate.js" || true

# verdict (strict)
console_err="$(grep -c '"type":"error"' "$EVID/console.jsonl" 2>/dev/null || true)"
page_err="$(wc -l < "$EVID/pageerror.jsonl" 2>/dev/null || echo 0)"
contract_fail="$(wc -l < "$EVID/contract_fail.jsonl" 2>/dev/null || echo 0)"
nav_fail="$(wc -l < "$EVID/nav_fail.jsonl" 2>/dev/null || echo 0)"

echo "[INFO] console_error_lines=$console_err pageerror_lines=$page_err contract_fail=$contract_fail nav_fail=$nav_fail" | tee -a "$EVID/summary.txt"

python3 - <<PY > "$EVID/verdict.json"
import json, datetime
v = {
  "ok": (${console_err}==0 and ${page_err}==0 and ${contract_fail}==0 and ${nav_fail}==0),
  "ts": datetime.datetime.now().isoformat(),
  "base": "$BASE",
  "evidence_dir": "$EVID",
  "console_error_lines": int(${console_err}),
  "pageerror_lines": int(${page_err}),
  "contract_fail": int(${contract_fail}),
  "nav_fail": int(${nav_fail}),
}
print(json.dumps(v, indent=2))
PY

cat "$EVID/verdict.json" | tee -a "$EVID/summary.txt"

if [ "$console_err" != "0" ] || [ "$page_err" != "0" ] || [ "$contract_fail" != "0" ] || [ "$nav_fail" != "0" ]; then
  echo "[FAIL] UI runtime gate FAILED. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  echo "[HINT] show details:" | tee -a "$EVID/summary.txt"
  echo "  cat $EVID/pageerror.jsonl | head -n 60" | tee -a "$EVID/summary.txt"
  echo "  grep '\"type\":\"error\"' $EVID/console.jsonl | head -n 60" | tee -a "$EVID/summary.txt"
  echo "  cat $EVID/contract_fail.jsonl | head -n 30" | tee -a "$EVID/summary.txt"
  exit 1
fi

echo "[PASS] UI runtime gate PASSED. Evidence=$EVID" | tee -a "$EVID/summary.txt"
