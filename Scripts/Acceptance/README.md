# Block Acceptance CI

This directory implements the low-cost development loop used before the final release workflow.

Pipeline:

`GitHub Validate -> block Fast Gate -> iterate -> one Block Full Acceptance -> merge -> next block -> one Full Release Gate after E`

## Commands

```bash
bash Scripts/Acceptance/run_block_gate.sh A fast
bash Scripts/Acceptance/run_block_gate.sh A full
```

The fast A gate captures 19 high-signal Motion V2 frames instead of all 223. The full A gate keeps the canonical 87 + 109 + 27 = 223-frame acceptance.

Blocks B-E are deliberately `ready: false` until their focused test selectors are added with the implementation. This is fail-closed: an unimplemented profile cannot report green.

## Cost rules

- GitHub/Linux performs portable checks and validates this CI configuration.
- macOS is used only for Xcode/simulator work.
- Fast gates never build an unsigned device Release app and never package an IPA.
- Block full gates are block-specific and run once before merge.
- `iosnext-free-sideload` remains the final release gate after A-E and retains device/IPA/signing/metadata validation.

## Scope guard

Use:

```bash
python3 Scripts/Acceptance/check_block_scope.py A --base <base-sha>
```

A scope mismatch is not automatically waived. Split the change or select a broader/full gate.
