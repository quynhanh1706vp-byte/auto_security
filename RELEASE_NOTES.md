# VSP UI Commercial Release (P0)

## Gate status
- P550: PASS (Run → Data → UI → Report export + support bundle)
- P559v2: PASS (commercial preflight)

## What ships (clean)
- `bin/ui_gate.sh`
- `bin/verify_release_and_customer_smoke.sh`
- `bin/pack_release.sh`
- `bin/ops.sh`

Patch scripts are **not shipped** as executables; they live in `bin/legacy/`.

## Templates included
- `config/systemd_unit.template`
- `config/logrotate_vsp-ui.template`
- `config/production.env.example`

## Release artifacts (in latest RELEASE_UI_*)
- `report_*.html`, `report_*.pdf`
- `support_bundle_*.tgz`
- `VSP_UI_*.tgz` (code package, clean excludes)
