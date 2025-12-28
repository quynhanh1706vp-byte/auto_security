# VSP UI Gateway — Commercial Install / Upgrade

## Files
- production.env (example config)
- install.sh (fresh install)
- upgrade.sh (upgrade existing install)
- support_bundle.sh (collect diagnostics for support)

## Quick start (fresh)
1) Extract release:
   tar -xzf VSP_UI_RELEASE.tgz
   cd VSP_UI_*

2) Copy config and edit:
   sudo mkdir -p /etc/vsp-ui
   sudo cp -f packaging/production.env /etc/vsp-ui/production.env
   sudo nano /etc/vsp-ui/production.env

3) Install:
   sudo ./packaging/install.sh

4) Smoke:
   curl -fsS http://127.0.0.1:8910/api/healthz && echo OK
   curl -fsS http://127.0.0.1:8910/api/readyz  && echo OK

## Upgrade
1) Extract new release and cd into it
2) sudo ./packaging/upgrade.sh
