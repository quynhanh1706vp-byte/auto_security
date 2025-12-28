VSP Commercial Release — FINAL (UI 5 tabs + ISO evidence)
UI:
  http://127.0.0.1:8910/vsp4  (Ctrl+Shift+R)
Tabs:
  Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides
Artifacts:
  - *__REPORT.tgz  (report + findings + __meta/iso)
  - AUDIT_BUNDLE_*.tgz (includes COMMERCIAL snapshot)
Verify:
  sha256sum -c RELEASE_SHA256SUMS.txt
