#!/usr/bin/env bash
set -euo pipefail

# P41 — Generate README_RELEASE.md + handover tar.gz for an existing release bundle
# Usage:
#   RELEASE_DIR=/path/to/RELEASE_UI_xxx RID=VSP_CI_xxx BASE=http://127.0.0.1:8910 bash bin/p41_proofnote_readme_and_handover_v1.sh
#
# Defaults match the provided release.

RELEASE_DIR="${RELEASE_DIR:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/RELEASE_UI_20251226_143439}"
RID="${RID:-VSP_CI_20251211_133204}"
BASE="${BASE:-${VSP_UI_BASE:-http://127.0.0.1:8910}}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need sha256sum; need tar; need awk; need sed; need grep; need ls; need wc; need head; need tail; need stat

[ -d "$RELEASE_DIR" ] || { echo "[ERR] RELEASE_DIR not found: $RELEASE_DIR"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
README="$RELEASE_DIR/README_RELEASE.md"

say(){ echo "[P41] $*"; }

# --- (A) Verify expected files (soft; warn if missing) ---
req_files=(
  "audit_v3b.txt"
  "EXPORT_SUMMARY.txt"
  "export_html.html"
  "export_pdf.pdf"
  "export_zip.zip"
  "runs.json"
  "RID.txt"
  "SHA256SUMS.txt"
)
missing=0
for f in "${req_files[@]}"; do
  if [ ! -f "$RELEASE_DIR/$f" ]; then
    echo "[WARN] missing expected file: $f"
    missing=$((missing+1))
  fi
done

# --- (B) Verify SHA256SUMS if present ---
sha_verdict="SKIP (SHA256SUMS.txt not found)"
if [ -f "$RELEASE_DIR/SHA256SUMS.txt" ]; then
  (
    cd "$RELEASE_DIR"
    if sha256sum -c SHA256SUMS.txt >/tmp/p41_sha_check_$$.log 2>&1; then
      sha_verdict="PASS (sha256sum -c OK)"
    else
      sha_verdict="FAIL (sha256sum -c mismatch)"
      echo "[ERR] SHA256SUMS verify failed. Log:"
      sed -n '1,200p' /tmp/p41_sha_check_$$.log
      exit 3
    fi
  )
  rm -f /tmp/p41_sha_check_$$.log || true
fi

# --- (C) Summaries ---
bytes_of(){ [ -f "$1" ] && wc -c <"$1" | tr -d ' ' || echo 0; }
size_audit="$(bytes_of "$RELEASE_DIR/audit_v3b.txt")"
size_html="$(bytes_of "$RELEASE_DIR/export_html.html")"
size_pdf="$(bytes_of "$RELEASE_DIR/export_pdf.pdf")"
size_zip="$(bytes_of "$RELEASE_DIR/export_zip.zip")"

verdict_line="$(grep -E '^\[VERDICT\]' "$RELEASE_DIR/audit_v3b.txt" 2>/dev/null | tail -n 1 || true)"
green_line="$(grep -E '^GREEN=' "$RELEASE_DIR/audit_v3b.txt" 2>/dev/null | tail -n 1 || true)"

# --- (D) Write README safely (atomic) ---
tmp="$(mktemp "$RELEASE_DIR/.README_RELEASE.md.tmp.XXXXXX")"
trap 'rm -f "$tmp" >/dev/null 2>&1 || true' EXIT

{
  echo "# P40 — Proofnote: Commercial UI Release (CIO / ISO 27001 / Audit-ready)"
  echo
  echo "## Release identity"
  echo "- Release folder (evidence bundle): \`$RELEASE_DIR\`"
  echo "- RID (selected run): \`$RID\`"
  echo "- Base URL (UI Gateway): \`$BASE\` (port 8910)"
  echo "- Generated at: \`$TS\`"
  echo
  echo "## 1) Scope & mục tiêu"
  echo "Bản phát hành UI Gateway (SECURITY_BUNDLE/VSP) đạt trạng thái **Commercial PASS** theo checklist P34–P39:"
  echo "- UI 5 tabs hoạt động + headers an toàn (**CSP-Report-Only**)."
  echo "- API contract ổn định (không 500/HTML rác)."
  echo "- Rule Overrides CRUD persist (tạo/sửa/xoá + reload vẫn còn)."
  echo "- Paging cho findings nhẹ + đúng offset."
  echo "- RID correctness: RID không tồn tại trả \`ok:false\` (không “lẫn cache cũ”)."
  echo "- Export report theo RID: HTML/PDF/ZIP đúng content-type, size > 0."
  echo
  echo "## 2) One-command reproduce (audit / sếp kiểm tra)"
  echo "Chạy lại audit thương mại (PASS/FAIL rõ ràng):"
  echo '```bash'
  echo "cd /home/test/Data/SECURITY_BUNDLE/ui"
  echo "VSP_UI_BASE=$BASE bash bin/commercial_ui_audit_v3b.sh"
  echo '```'
  echo "Kết quả mong đợi: **AMBER=0, RED=0** và \`[VERDICT] PASS\`."
  echo
  echo "## 3) Evidence artifacts (bằng chứng trong release bundle)"
  echo "Các file chính:"
  echo "- \`audit_v3b.txt\` — log audit P38/P39 (verdict PASS)."
  echo "- \`EXPORT_SUMMARY.txt\` — header + bytes của html/pdf/zip."
  echo "- \`export_html.html\`, \`export_pdf.pdf\`, \`export_zip.zip\` — file export thực tế."
  echo "- \`export_*.hdr\` — headers chứng minh content-type/disposition."
  echo "- \`runs.json\`, \`RID.txt\` — snapshot run selection."
  echo "- \`SHA256SUMS.txt\` — checksum chống chỉnh sửa (tamper-evidence)."
  echo
  echo "### Quick stats"
  echo "- audit_v3b.txt bytes: $size_audit"
  echo "- export_html.html bytes: $size_html"
  echo "- export_pdf.pdf bytes: $size_pdf"
  echo "- export_zip.zip bytes: $size_zip"
  echo "- SHA256 verify: $sha_verdict"
  [ -n "$green_line" ] && echo "- Audit summary: $green_line"
  [ -n "$verdict_line" ] && echo "- Audit verdict: $verdict_line"
  echo
  echo "## 4) Contract quan trọng (CIO-level “đóng đinh”)"
  echo "- CSP-Report-Only: tất cả tab trả về đúng header (1 lần / response)."
  echo "- Rule Overrides: POST/DELETE hoạt động; dữ liệu persist tại:"
  echo "  - \`/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1/rule_overrides.json\`"
  echo "- Paging findings: \`/api/vsp/findings?limit=5&offset=N\` trả payload nhỏ (không bắn hàng chục MB như trước)."
  echo "- RID missing: \`/api/vsp/datasource_v2?rid=RID_DOES_NOT_EXIST_123\` trả:"
  echo '  ```json'
  echo '  {"ok":false,"reason":"run_dir_not_found", ...}'
  echo '  ```'
  echo
  echo "## 5) ISO 27001 mapping gợi ý (không ghi số điều khoản Annex A)"
  echo "- Logging & Monitoring: \`audit_v3b.txt\`, headers, export evidence → chứng minh kiểm tra vận hành & theo dõi."
  echo "- Integrity / Tamper evidence: \`SHA256SUMS.txt\` → chứng minh tính toàn vẹn bộ bằng chứng."
  echo "- Secure configuration: CSP-RO + API JSON contract → giảm rủi ro XSS/misconfig."
  echo "- Change management / Release evidence: release folder theo timestamp + RID snapshot → truy vết được “ai/when/what”."
  echo
  echo "## 6) Evidence inventory (ls -lh)"
  echo '```'
  (cd "$RELEASE_DIR" && ls -lh)
  echo '```'
  echo
  echo "## 7) Notes"
  echo "- Bundle này là **self-contained**: có log audit, export outputs, headers, RID snapshot, và checksum."
  echo "- Khi cần bàn giao: gửi kèm gói handover \`.tar.gz\` tạo bởi P41."
} > "$tmp"

chmod 0644 "$tmp"
mv -f "$tmp" "$README"
trap - EXIT
say "Wrote: $README"

# --- (E) Build handover tar.gz (contains the whole release folder) ---
parent="$(dirname "$RELEASE_DIR")"
base="$(basename "$RELEASE_DIR")"
handover="$parent/HANDOVER_${base}_RID_${RID}_${TS}.tar.gz"

(
  cd "$parent"
  tar -czf "$handover" "$base"
)

say "Created handover: $handover"
say "Done. Missing_expected_files=$missing"
