# INDEX_ACTIVE_SCRIPTS (Commercial Reachable)

- Generated: 20251226_151643
- Root: /home/test/Data/SECURITY_BUNDLE/ui
- Seeds: 12 | Reachable scripts: 15

## A) Commercial entrypoints (seeds)

| Script | Purpose | Run |
|---|---|---|
| `p43_bin_syntax_gate.sh` | — | `bash bin/p43_bin_syntax_gate.sh` |
| `commercial_ui_audit_v3b.sh` | P38: commercial_ui_audit_v3b ==" | `bash bin/commercial_ui_audit_v3b.sh` |
| `p46_gate_pack_handover_v1.sh` | — | `bash bin/p46_gate_pack_handover_v1.sh` |
| `p39_pack_commercial_release_v1b.sh` | 0: warm selfcheck ==" | `bash bin/p39_pack_commercial_release_v1b.sh` |
| `p2_release_pack_ui_commercial_v1.sh` | 1: Run smoke audit ==" | `bash bin/p2_release_pack_ui_commercial_v1.sh` |
| `p1_release_proofnote_v2_fixed.sh` | — | `bash bin/p1_release_proofnote_v2_fixed.sh` |
| `vsp_ui_ops_safe_v3.sh` | 1: wait port ==" | `bash bin/vsp_ui_ops_safe_v3.sh` |
| `commercial_ui_audit_v1.sh` | A: fetch HTML per tab + extract JS ==" | `bash bin/commercial_ui_audit_v1.sh` |
| `commercial_ui_audit_v2.sh` | — | `bash bin/commercial_ui_audit_v2.sh` |
| `commercial_ui_audit_v3.sh` | P38: commercial_ui_audit_v3 ==" | `bash bin/commercial_ui_audit_v3.sh` |
| `commercial_ui_audit_v3b.sh` | P38: commercial_ui_audit_v3b ==" | `bash bin/commercial_ui_audit_v3b.sh` |
| `p44_index_inventory_v1.sh` | X: ... | `bash bin/p44_index_inventory_v1.sh` |

## B) Reachable dependencies (called by seeds)

| Script | Purpose | Run |
|---|---|---|
| `p0_market_release_pack_v1.sh` | — | `bash bin/p0_market_release_pack_v1.sh` |
| `p0_rollback_last_good_v1.sh` | — | `bash bin/p0_rollback_last_good_v1.sh` |
| `p2_ui_commercial_smoke_audit_v1.sh` | 0: Basic endpoints reachable ==" | `bash bin/p2_ui_commercial_smoke_audit_v1.sh` |
| `p43_bin_syntax_gate.py` | P43: bin syntax gate ==") | `python3 bin/p43_bin_syntax_gate.py` |

## C) Not listed
- Legacy/one-off/patch scripts are intentionally not listed here to keep this file readable.
- To browse all scripts: `ls -1 bin/*.sh bin/*.py | wc -l`
