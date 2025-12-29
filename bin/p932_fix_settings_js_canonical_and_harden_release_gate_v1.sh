#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p932_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need node; need python3; need git; need date; need curl

SETJS="static/js/vsp_c_settings_v1.js"

echo "== [P932] 1) JS syntax check (current) =="
if node --check "$SETJS" >/dev/null 2>"$OUT/node_check.err"; then
  echo "[OK] settings js syntax OK: $SETJS" | tee -a "$OUT/log.txt"
else
  echo "[WARN] settings js syntax FAIL: $SETJS" | tee -a "$OUT/log.txt"
  head -n 30 "$OUT/node_check.err" | tee -a "$OUT/log.txt" || true

  echo "== [P932] 2) Restore from latest GOLDEN backup (.bak_GOOD_*) =="
  GOLDEN="$(ls -1t "${SETJS}.bak_GOOD_"* 2>/dev/null | head -n1 || true)"
  if [ -z "${GOLDEN:-}" ]; then
    echo "[ERR] no GOLDEN backup found for $SETJS (expected ${SETJS}.bak_GOOD_*)"
    echo "Tip: run your known-good builder (p923b) once, then mark it as .bak_GOOD_*."
    exit 3
  fi
  cp -f "$GOLDEN" "$SETJS"
  echo "[OK] restored GOLDEN: $GOLDEN -> $SETJS" | tee -a "$OUT/log.txt"

  node --check "$SETJS" >/dev/null
  echo "[OK] after restore, syntax OK" | tee -a "$OUT/log.txt"
fi

echo "== [P932] 3) Stamp a new GOLDEN snapshot (canonical) =="
cp -f "$SETJS" "${SETJS}.bak_GOOD_${TS}"
echo "[OK] wrote ${SETJS}.bak_GOOD_${TS}" | tee -a "$OUT/log.txt"

echo "== [P932] 4) Create STRICT JS gate (no autorollback) =="
cat > bin/p934_js_syntax_gate_strict_v1.sh <<'GATE'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node

FILES=(
  "static/js/vsp_c_settings_v1.js"
  "static/js/vsp_ops_panel_v1.js"
  "static/js/vsp_c_sidebar_v1.js"
  "static/js/vsp_c_runs_v1.js"
  "static/js/vsp_data_source_tab_v3.js"
)

echo "== [P934] JS syntax STRICT gate =="
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "[FAIL] missing: $f"
    exit 3
  fi
  if node --check "$f" >/dev/null 2>&1; then
    echo "[OK] $f"
  else
    echo "[FAIL] js syntax: $f"
    node --check "$f" || true
    exit 4
  fi
done
echo "[OK] P934 gate PASS"
GATE
chmod +x bin/p934_js_syntax_gate_strict_v1.sh
bash bin/p934_js_syntax_gate_strict_v1.sh | tee -a "$OUT/log.txt"

echo "== [P932] 5) Patch pack script to enforce strict gate before release =="
PACK="bin/p922b_pack_release_snapshot_no_warning_v2.sh"
if [ -f "$PACK" ]; then
  python3 - <<'PY'
from pathlib import Path
import datetime, re
pack = Path("bin/p922b_pack_release_snapshot_no_warning_v2.sh")
s = pack.read_text(encoding="utf-8", errors="replace")
tag = "P932_ENFORCE_P934_JS_GATE"
if tag in s:
    print("[OK] pack already enforces P934 gate")
    raise SystemExit(0)

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bk = Path(str(pack) + f".bak_p932_{ts}")
bk.write_text(s, encoding="utf-8")
print("[OK] backup =>", bk)

# Insert after need blocks (best-effort)
ins = '\n# P932_ENFORCE_P934_JS_GATE\nbash bin/p934_js_syntax_gate_strict_v1.sh\n'
m = re.search(r'(^need\s+rsync\s*\n)', s, flags=re.M)
if m:
    s2 = s[:m.end(1)] + ins + s[m.end(1):]
else:
    # fallback: insert after last "need ..." line
    lines = s.splitlines(True)
    last_need = 0
    for i,ln in enumerate(lines):
        if ln.strip().startswith("need "):
            last_need = i+1
    s2 = "".join(lines[:last_need]) + ins + "".join(lines[last_need:])

pack.write_text(s2, encoding="utf-8")
print("[OK] patched pack to enforce P934 gate")
PY
  bash -n "$PACK" | tee -a "$OUT/log.txt"
else
  echo "[WARN] pack script not found: $PACK (skip patch)" | tee -a "$OUT/log.txt"
fi

echo "== [P932] 6) Restart service + smoke =="
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

# wait ready
ok=0
for i in $(seq 1 30); do
  code="$(curl -sS --noproxy '*' -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/api/vsp/healthz" || true)"
  echo "try#$i code=$code" | tee -a "$OUT/log.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done
[ "$ok" = "1" ] || { echo "[FAIL] UI not ready"; exit 5; }

bash bin/p918_p0_smoke_no_error_v1.sh | tee -a "$OUT/log.txt"

echo "== [P932] 7) Commit canonical + gates (no more random break) =="
git add "$SETJS" "${SETJS}.bak_GOOD_${TS}" bin/p934_js_syntax_gate_strict_v1.sh "$PACK" 2>/dev/null || true
git commit -m "p0: canonicalize settings JS + strict JS gate in pack/CI (P932/P934)" || true
git push || true

echo "[OK] P932 done. Evidence: $OUT"
echo "Open: ${BASE}/c/settings (Ctrl+Shift+R) and ensure console has NO SyntaxError."
