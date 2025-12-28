# RUNBOOK — VSP Commercial UI

## Service
- systemd: vsp-ui-8910.service
- Status:  sudo systemctl status vsp-ui-8910.service --no-pager
- Restart: sudo systemctl restart vsp-ui-8910.service

## Health
- UI health: /api/vsp/ui_health_v2?rid=<RID>

## Logs
- Check service logs:
  journalctl -u vsp-ui-8910.service -n 200 --no-pager

## Common issues (Commercial-grade)
1) KPI shows N/A
- Commercial UI must not display N/A as final state.
- Show 0 / “—” + tooltip (“No data for selected RID”), and ensure API returns full counts.

2) Releases not available
- Check: GET /api/vsp/release_latest includes download_url + audit_url.

3) Console red / assets blocked
- Verify JS asset URL returns 200 with correct JS content-type.
- Browser “allow pasting” warning is NOT an app error.

4) Data Source empty / slow
- Commercial contract should use dedicated paging/filter API.
- Avoid FE calling run_file_allow with internal file paths.
