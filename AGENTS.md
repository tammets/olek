# Agent guidance

## Code Review Rules

- Report every real defect you can back with a concrete failure scenario, including P2 and P3 issues. Do not limit comments to P0 and P1.
- Check what happens when two requests or transactions overlap with the changed code.
- Check for data loss: what gets deleted or overwritten, including through cascades and scheduled jobs.
- When the change adds a guard or a required path, look for other code paths that bypass it.
- Check that the pull request description matches what the code does.
- Check that new tests would fail without the change.
- Leave formatting and lint issues to CI.
