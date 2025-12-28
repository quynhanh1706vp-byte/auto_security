#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need head

tmp="$(mktemp -d /tmp/vsp_ui_feature_gap_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fetch(){
  local p="$1" f="$2"
  curl -fsS "$BASE$p" -o "$tmp/$f"
}

fetch /vsp5 _vsp5.html
fetch /runs _runs.html
fetch /data_source _data_source.html
fetch /settings _settings.html
fetch /rule_overrides _rule_overrides.html

say(){ printf "\n== %s ==\n" "$*"; }
have(){ grep -qiE "$2" "$tmp/$1"; }

check(){
  local file="$1" name="$2" pat="$3"
  if have "$file" "$pat"; then
    echo "[OK]   $name"
  else
    echo "[MISS] $name"
  fi
}

say "DASHBOARD (/vsp5) core"
check _vsp5.html "dashboard main anchor" 'id="vsp-dashboard-main"|#vsp-dashboard-main'
check _vsp5.html "topbar present" 'topbar|vsp-topbar|nav|header'
check _vsp5.html "tab navigation present" 'runs|data_source|settings|rule_overrides'
check _vsp5.html "export/download actions" 'download|export|package|release|report|pdf|zip'
check _vsp5.html "degraded banner (KPI disabled)" 'degraded|disabled by policy|KPI.*disabled|VSP_SAFE_DISABLE_KPI|__via__'

say "RUNS (/runs)"
check _runs.html "runs table/list" 'table|Runs|rid|RUN_|VSP_CI'
check _runs.html "runs actions (view/download)" 'download|view|open|report|zip|html|pdf'

say "DATA SOURCE (/data_source)"
check _data_source.html "filter/search UI" 'filter|search|query|input'
check _data_source.html "export json/csv" 'csv|json|export|download'

say "SETTINGS (/settings)"
check _settings.html "tool list/policy text" 'Semgrep|Gitleaks|KICS|Trivy|Syft|Grype|Bandit|CodeQL|policy|timeout'

say "RULE OVERRIDES (/rule_overrides)"
check _rule_overrides.html "editor present" 'textarea|editor|override|rule'
check _rule_overrides.html "save/apply present" 'save|apply|submit|POST|/api/ui/rule_overrides'

say "NOTE"
echo "This is heuristic (HTML keywords). If a section is built entirely by JS, it may not show in raw HTML."
