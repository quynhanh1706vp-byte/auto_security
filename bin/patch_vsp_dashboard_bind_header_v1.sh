#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_bind_header_$(date +%Y%m%d_%H%M%S)"

echo "[BACKUP] $TPL -> $BACKUP"
cp "$TPL" "$BACKUP"

python - << 'PY'
import pathlib

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

if "VSP_DASH_BIND_HEADER" in txt:
    print("[PATCH] Header binding đã có – skip.")
    raise SystemExit(0)

marker = "</body>"
idx = txt.rfind(marker)
if idx == -1:
    raise SystemExit("[ERR] Không tìm thấy </body> trong template.")

snippet = """
  <script>
    // [VSP_DASH_BIND_HEADER] Nối header với /api/vsp/dashboard_v3
    (async function() {
      try {
        const res = await fetch('/api/vsp/dashboard_v3');
        if (!res.ok) {
            console.warn('[VSP_DASH_BIND_HEADER] HTTP', res.status);
            return;
        }
        const data = await res.json();

        // Total findings
        const t = document.getElementById('vsp-header-total-findings');
        if (t && data.total_findings != null) {
          try {
            const n = Number(data.total_findings);
            t.textContent = Number.isFinite(n) ? n.toLocaleString() : String(data.total_findings);
          } catch (e) {
            t.textContent = String(data.total_findings);
          }
        }

        // Security posture score
        const s = document.getElementById('vsp-header-score');
        if (s && data.security_posture_score != null) {
          s.textContent = data.security_posture_score;
        }

        // Latest run id
        const r = document.getElementById('vsp-latest-run-id');
        if (r && data.latest_run_id) {
          r.textContent = 'RUN: ' + data.latest_run_id;
        }
      } catch (e) {
        console.warn('[VSP_DASH_BIND_HEADER] Error', e);
      }
    })();
  </script>
"""

txt = txt[:idx] + snippet + "\n" + txt[idx:]
tpl_path.write_text(txt, encoding="utf-8")
print("[PATCH] Đã inject header binding script trước </body>.")
PY
