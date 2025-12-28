# VSP UI Commercial Release

- Timestamp: 20251224_104852
- Base URL: http://127.0.0.1:8910
- Latest RID: VSP_CI_20251218_114312

## Included
- wsgi_vsp_ui_gateway.py (gateway)
- vsp_data_source_lazy_v1.js (contract-only)
- smoke_audit.log (GREEN/AMBER/RED summary)
- captured HTML: /vsp5 /runs /data_source /settings /rule_overrides

## Acceptance (expected)
- Tabs return HTTP 200
- /api/vsp/run_file_allow findings_unified.json returns non-empty `findings`
- No X-VSP-RFA* debug headers
- DS lazy Cache-Control: no-store
