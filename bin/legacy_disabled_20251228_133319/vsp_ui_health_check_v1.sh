#!/usr/bin/env bash
set -euo pipefail

# VSP UI health check – kiểm tra nhanh 5 API tương ứng 5 tab:
# 1) Dashboard
# 2) Data Source
# 3) Runs & Reports
# 4) Settings
# 5) Rule Overrides

BASE_URL="${VSP_UI_BASE:-http://localhost:8910}"

log() {
  local level="$1"; shift
  printf '[VSP_UI_HEALTH][%s] %s\n' "$level" "$*"
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "ERR" "Thiếu lệnh bắt buộc: $cmd"
    exit 1
  fi
}

need_cmd curl
need_cmd jq

check_endpoint() {
  local name="$1"
  local path="$2"
  local jq_expr="$3"

  log "INFO" "=== Check: $name ($path) ==="
  local tmp
  tmp="$(mktemp)"

  local url="${BASE_URL}${path}"
  local http_code
  http_code="$(curl -sS -o "$tmp" -w '%{http_code}' "$url" || echo "000")"

  if [[ "$http_code" != "200" ]]; then
    log "ERR" "$name: HTTP $http_code từ $url"
    log "ERR" "$name: body (rút gọn):"
    head -c 400 "$tmp" || true
    echo
    rm -f "$tmp"
    return 1
  fi

  # Thử parse JSON
  if ! jq '.' "$tmp" >/dev/null 2>&1; then
    log "ERR" "$name: phản hồi không phải JSON hợp lệ."
    head -c 400 "$tmp" || true
    echo
    rm -f "$tmp"
    return 1
  fi

  # Nếu có biểu thức jq summary thì hiển thị
  if [[ -n "$jq_expr" ]]; then
    log "OK"  "$name: HTTP 200 – tóm tắt:"
    jq -r "$jq_expr" "$tmp" || true
  else
    log "OK"  "$name: HTTP 200 – JSON hợp lệ."
  fi

  rm -f "$tmp"
  echo
}

log "INFO" "Kiểm tra VSP UI tại BASE_URL = $BASE_URL"

# 1) Dashboard – CIO tab
check_endpoint \
  "Dashboard" \
  "/api/vsp/dashboard_v3" \
  '{
    latest_run_id: .latest_run_id,
    total_findings: .total_findings,
    security_posture_score: .security_posture_score,
    by_severity: .severity_cards
  }'

# 2) Data Source – bảng findings
check_endpoint \
  "DataSource" \
  "/api/vsp/datasource_v2?limit=3" \
  '{
    total: .total,
    sample_items: (.items[0:3] | map({tool, severity, rule_id, file}) )
  }'

# 3) Runs & Reports – danh sách run
check_endpoint \
  "RunsIndex" \
  "/api/vsp/runs_index_v3?limit=5" \
  '{
    count: (.items | length),
    runs: (.items | map({run_id, kind, created_at, total_findings}) )
  }'

# 4) Settings tab
check_endpoint \
  "SettingsUI" \
  "/api/vsp/settings_ui_v1" \
  '{
    ok: .ok,
    settings_type: (.settings | type),
    keys: (.settings | keys?)
  }'

# 5) Rule Overrides tab
check_endpoint \
  "RuleOverridesUI" \
  "/api/vsp/rule_overrides_ui_v1" \
  '{
    ok: .ok,
    overrides_count: (
      if has("overrides") and (.overrides | type == "array")
      then (.overrides | length)
      else null
      end
    )
  }'

log "INFO" "Hoàn tất VSP UI health check."
