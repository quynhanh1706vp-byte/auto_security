# VSP UI Gateway — Runbook (P0 Ops)

## Paths
- Root: /home/test/Data/SECURITY_BUNDLE/ui
- Artifacts: out_ci/
- Runner unit (user): gh-runner.service (env: GH_RUNNER_UNIT)

## UI service
```bash
sudo systemctl status vsp-ui-8910.service --no-pager -l
sudo systemctl restart vsp-ui-8910.service
sudo journaltl -u vsp-ui-8910.service -n 200 --no-pager
```

## Runner (no-sudo)
```bash
cd /home/test/Data/SECURITY_BUNDLE/ui
bash bin/ops/runner_service_user_v1.sh install
bash bin/ops/runner_service_user_v1.sh status
bash bin/ops/runner_service_user_v1.sh logs
```

Boot without login (ops-only, 1 lần):
```bash
sudo loginctl enable-linger $USER
```

## Healthceck (with evidence)
```bash
bash bin/ops/healthceck_ci_v1.sh
```
Evidence: out_ci/ops_healthceck/<TS>/
