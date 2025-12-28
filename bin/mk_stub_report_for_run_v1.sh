#!/usr/bin/env bash
set -euo pipefail

RID="${1:-RUN_VSP_CI_20251215_034956}"
RUN_DIR="/home/test/Data/SECURITY-10-10-v4/out_ci/${RID#RUN_}"

RPT_DIR="$RUN_DIR/reports"
mkdir -p "$RPT_DIR"

OUT="$RPT_DIR/vsp_run_report_cio_v3.html"

cat > "$OUT" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>VSP Report (Stub) - $RID</title>
<style>
  body{font-family:system-ui,Segoe UI,Roboto,Arial; background:#0b1220; color:#e5e7eb; margin:0; padding:24px;}
  .card{background:rgba(255,255,255,0.06); border:1px solid rgba(255,255,255,0.10); border-radius:16px; padding:16px; margin:12px 0;}
  .k{opacity:.85; font-size:12px; text-transform:uppercase; letter-spacing:.06em;}
  .v{font-size:14px; margin-top:6px;}
  a{color:#93c5fd;}
</style>
</head>
<body>
<h2>VSP Commercial Report (Stub)</h2>
<div class="card">
  <div class="k">RID</div><div class="v">$RID</div>
  <div class="k">RUN_DIR</div><div class="v">$RUN_DIR</div>
  <div class="k">Note</div><div class="v">This is a stub report generated to enable HTML export button. Replace with real report generator in P2.</div>
</div>
</body>
</html>
EOF

echo "[OK] wrote $OUT"
ls -la "$OUT"
