P42 quarantine at 20251226_144708
Moved scripts that FAIL: bash -n

- fix_latest_findings_unified_from_reports_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/fix_latest_findings_unified_from_reports_v1.sh: dòng 48: cảnh báo: tài liệu này ở dòng 16 định giới bằng kết thúc tập tin (muốn “PY”)
    /home/test/Data/SECURITY_BUNDLE/ui/bin/fix_latest_findings_unified_from_reports_v1.sh: dòng 49: lỗi cú pháp: kết thúc tập tin bất thường

- fix_patch_runs_api_verify_no_jsondecode_p0_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/fix_patch_runs_api_verify_no_jsondecode_p0_v1.sh: dòng 41: có lỗi cú pháp ở gần thẻ bài bất thường “fi”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/fix_patch_runs_api_verify_no_jsondecode_p0_v1.sh: dòng 41: `fi'

- p0_fix_luxe_loaded_only_on_vsp5_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_fix_luxe_loaded_only_on_vsp5_v1.sh: dòng 15: có lỗi cú pháp ở gần thẻ bài bất thường “2”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_fix_luxe_loaded_only_on_vsp5_v1.sh: dòng 15: `for f in templates/*.html templates/**/*.html 2>/dev/null; do cand+=("$f"); done'

- p0_recover_then_fix_runfileallow_missing_guard_v3.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_recover_then_fix_runfileallow_missing_guard_v3.sh: dòng 194: cảnh báo: tài liệu này ở dòng 40 định giới bằng kết thúc tập tin (muốn “PY”)
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_recover_then_fix_runfileallow_missing_guard_v3.sh: dòng 195: lỗi cú pháp: kết thúc tập tin bất thường

- p0_restore_pass_backup_and_repatch_safe_v1i.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_restore_pass_backup_and_repatch_safe_v1i.sh: dòng 64: có lỗi cú pháp ở gần thẻ bài bất thường “(”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_restore_pass_backup_and_repatch_safe_v1i.sh: dòng 64: `  x = x.replace(\'"/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json"\','

- p1_fix_release_script_manifest_block_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p1_fix_release_script_manifest_block_v1.sh: dòng 54: gặp kết thúc tập tin bất thường trong khi tìm “'” tương ứng

- p1_tabs3_bundle_commercialize_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p1_tabs3_bundle_commercialize_v1.sh: dòng 849: có lỗi cú pháp ở gần thẻ bài bất thường “)”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p1_tabs3_bundle_commercialize_v1.sh: dòng 849: `  )'

- p1_tabs3_realdata_enrich_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p1_tabs3_realdata_enrich_v1.sh: dòng 489: có lỗi cú pháp ở gần thẻ bài bất thường “(”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p1_tabs3_realdata_enrich_v1.sh: dòng 489: `for f in ("static/js/vsp_settings_tab_v3.js","static/js/vsp_rule_overrides_tab_v3.js"):'

- p1_ui_fix_bundle_invalid_token_p1_3_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p1_ui_fix_bundle_invalid_token_p1_3_v1.sh: dòng 58: cảnh báo: tài liệu này ở dòng 21 định giới bằng kết thúc tập tin (muốn “PY”)
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p1_ui_fix_bundle_invalid_token_p1_3_v1.sh: dòng 59: lỗi cú pháp: kết thúc tập tin bất thường

- p2_fix_commercial_selfcheck_releases_v2.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p2_fix_commercial_selfcheck_releases_v2.sh: dòng 65: có lỗi cú pháp ở gần thẻ bài bất thường “else”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/p2_fix_commercial_selfcheck_releases_v2.sh: dòng 65: `else'

- patch_bootstrap_autodiscover_dash_endpoint_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_bootstrap_autodiscover_dash_endpoint_v1.sh: dòng 77: có lỗi cú pháp ở gần thẻ bài bất thường “fi”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_bootstrap_autodiscover_dash_endpoint_v1.sh: dòng 77: `fi'

- patch_fix_nav_endpoints_v2.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_fix_nav_endpoints_v2.sh: dòng 40: có lỗi cú pháp ở gần thẻ bài bất thường “"[WARN] Không tìm thấy template nào chứa url_for('runs') hoặc url_for('datasource')."”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_fix_nav_endpoints_v2.sh: dòng 40: `  print("[WARN] Không tìm thấy template nào chứa url_for('runs') hoặc url_for('datasource').")'

- patch_scan_settings_iso_and_menu.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_scan_settings_iso_and_menu.sh: dòng 7: có lỗi cú pháp ở gần thẻ bài bất thường “(”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_scan_settings_iso_and_menu.sh: dòng 7: `root = Path("templates")'

- patch_wsgi_dedupe_mark_safe_alias_p0_v8b_fix.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_wsgi_dedupe_mark_safe_alias_p0_v8b_fix.sh: dòng 32: có lỗi cú pháp ở gần thẻ bài bất thường “(”
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_wsgi_dedupe_mark_safe_alias_p0_v8b_fix.sh: dòng 32: `             "# (P0_V8B) disabled legacy MARK reassignment", txt)'

- patch_wsgi_statusv2_always8_v1.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_wsgi_statusv2_always8_v1.sh: dòng 175: gặp kết thúc tập tin bất thường trong khi tìm “"” tương ứng

- vsp_commercial_gate_v3.sh
    /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_commercial_gate_v3.sh: dòng 56: cảnh báo: tài liệu này ở dòng 21 định giới bằng kết thúc tập tin (muốn “EOF”)
    /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_commercial_gate_v3.sh: dòng 57: lỗi cú pháp: kết thúc tập tin bất thường

