VSP Commercial Release (UI 5 tabs + ISO evidence)
1) Verify integrity:
   sha256sum -c RELEASE_SHA256SUMS.txt

2) UI:
   http://127.0.0.1:8910/vsp4  (Ctrl+Shift+R)
   Tabs: Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides
   Buttons: Open HTML / Export TGZ / Verify SHA

3) Report content:
   tar -tzf VSP_CI_*__REPORT.tgz | grep -E 'report/__meta/iso/(ISO_EVIDENCE_INDEX\.json|ISO_27001_MAP\.csv)'

4) Audit bundle:
   tar -tzf AUDIT_BUNDLE_*.tgz | head
