VSP Commercial Release (UI 5 tabs + ISO evidence)
RID: VSP_CI_20251215_034956
RUN_DIR: /home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_20251215_034956

1) Verify integrity:
   sha256sum -c RELEASE_SHA256SUMS.txt

2) UI:
   http://127.0.0.1:8910/vsp4  (Ctrl+Shift+R)
   Tabs: Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides

3) Report content check ISO:
   tar -tzf VSP_CI_20251215_034956__REPORT.tgz | grep -E 'report/__meta/iso/(ISO_EVIDENCE_INDEX\.json|ISO_27001_MAP\.csv)'

4) Audit bundle:
   tar -tzf AUDIT_BUNDLE_VSP_CI_20251215_034956_20251218_094523.tgz | head
