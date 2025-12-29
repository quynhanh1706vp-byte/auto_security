#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [P923] P921C settings js guard =="
bash bin/p921c_fix_settings_js_syntax_autorollback_or_fallback_v1.sh

echo "== [P923] P918 smoke =="
bash bin/p918_p0_smoke_no_error_v1.sh

echo "== [P923] P920 ops evidence (journal/logtail/evidence.zip) =="
bash bin/p920_p0plus_ops_evidence_logs_v1.sh

echo "== [P923] P922B pack release snapshot =="
bash bin/p922b_pack_release_snapshot_no_warning_v2.sh

echo "[OK] P923 DONE"
