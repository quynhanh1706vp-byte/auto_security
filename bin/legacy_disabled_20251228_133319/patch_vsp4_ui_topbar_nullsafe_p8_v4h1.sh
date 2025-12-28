#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_UI_TOPBAR_QUICKACTIONS_P8_V4"
FIX="VSP_UI_TOPBAR_NULLSAFE_P8_V4H1"

echo "== PATCH TOPBAR NULL-SAFE P8.V4H1 =="
echo "[TS]=$TS"

# patch all templates containing our marker
mapfile -t FILES < <(grep -rl --include='*.html' "$MARK" templates 2>/dev/null || true)
[ ${#FILES[@]} -gt 0 ] || { echo "[ERR] cannot find templates with marker: $MARK"; exit 2; }

printf "[FILES]=%s\n" "${#FILES[@]}"
printf " - %s\n" "${FILES[@]}"

export FILES_NL="$(printf "%s\n" "${FILES[@]}")"
export TS
python3 - <<'PY'
import os, re
from pathlib import Path

MARK="VSP_UI_TOPBAR_QUICKACTIONS_P8_V4"
FIX="VSP_UI_TOPBAR_NULLSAFE_P8_V4H1"

files=[x.strip() for x in os.environ.get("FILES_NL","").splitlines() if x.strip()]
patched=0

for f in files:
    p=Path(f)
    s=p.read_text(encoding="utf-8", errors="replace")
    if FIX in s:
        print("[SKIP] already:", p); 
        continue

    # backup
    b = p.with_suffix(p.suffix + f".bak_{FIX}_{os.environ.get('TS','')}")
    try:
        b.write_text(s, encoding="utf-8")
        print("[BACKUP]", b)
    except Exception:
        pass

    # Replace the brittle updateDegraded() block with a null-safe + re-injectable version
    # Target: inside <script id="vspTopbarJsP8v4"> ... </script>
    def repl(m):
        body = m.group(0)

        # if already contains our safeSetText, skip minimal
        if "function safeSetText" in body:
            return body + "\n<!-- " + FIX + " -->\n"

        safe = r'''
  function safeGet(id){ try { return document.getElementById(id); } catch(_){ return null; } }
  function safeSetText(id, txt){
    const el = safeGet(id);
    if (el) el.textContent = txt;
  }
  function ensureTopbar(){
    // if topbar got wiped by SPA re-render, do nothing (avoid errors); we only silence console
    return !!safeGet("vspTopbarP8v4");
  }
  function updateDegraded(){
    if (!ensureTopbar()) return;
    fetch("/api/vsp/dashboard_commercial_v2?ts=" + Date.now())
      .then(r=>r.json())
      .then(j=>{
        const yes = !!(((j||{}).overall||{}).degraded_yes);
        safeSetText("vspChipDegradedP8v4", "DEGRADED: " + (yes ? "YES" : "NO"));
      })
      .catch(()=>{
        safeSetText("vspChipDegradedP8v4", "DEGRADED: N/A");
      });
  }
  updateDegraded();
  setInterval(updateDegraded, 15000);
'''
        # remove old updateDegraded() + setInterval area (best-effort)
        body2 = re.sub(
            r'\s*function updateDegraded\(\)\{.*?\}\s*updateDegraded\(\);\s*setInterval\(updateDegraded,\s*15000\);\s*',
            "\n" + safe + "\n",
            body,
            flags=re.DOTALL
        )
        return body2 + "\n<!-- " + FIX + " -->\n"

    s2 = re.sub(r'(<script id="vspTopbarJsP8v4">.*?</script>)', repl, s, flags=re.DOTALL)
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched:", p)
    patched += 1

print("[DONE] patched_files=", patched)
PY

echo "== HARD RESET 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "[NEXT] Ctrl+Shift+R http://127.0.0.1:8910/vsp4  (Console phải hết đỏ)"
