# ATHLTH development baseline

- Active development version: 1.7.5 on `release/v1.7.5`, initial build number 81.
- Version 1.7.4 is locked for new development. Frozen commit: `61038f37a11a69cb9e4163d85fb24a82514b0a85` (build 80; TestFlight upload succeeded). Preservation branch: `backup/v1.7.4-locked-before-v1.7.5-20261014`.
- Version 1.7.3 is locked for new development. Frozen commit: `f551ffb02fa78e6b370a7a40288092b3f70e9106` (build 79). Preservation branch: `backup/v1.7.3-locked-before-v1.7.4-20261012`.
- Versions 1.7.2 and 1.7.1 are locked; preservation branches: `backup/v1.7.2-locked-before-v1.7.3-20261011` and `backup/v1.7.1-locked-before-v1.7.2-20261011`.
- Version 1.7.0 is locked and must not receive further development changes. Frozen commit: `e001d3aa8300e1e4309bd08b18ccfd856fe59ad3` (build 76; iOS build, backend regressions and TestFlight upload succeeded).
- Preservation branch: `backup/v1.7.0-locked-before-v1.7.1-20261010`.
- Version 1.6.9 is locked. Do not modify `release/v1.6.9` for new development.
- Frozen 1.6.9 commit: `cdc02dc313a20f8430cc96fb882b7fa2e09850d5` (build 75, published to TestFlight).
- Preservation branch: `backup/v1.6.9-locked-before-v1.7.0-20261009`.
- Version 1.6.8 is also locked. Frozen commit: `ae61b6643bb06ec542c71743ccdbef43b83a0a88` (build 74).
- Preservation branch: `backup/v1.6.8-locked-before-v1.6.9-20261008`.
- All previous released versions remain closed for new development.
- Make future fixes and design work only on the active release branch unless the user explicitly directs otherwise.
- Preserve existing Quick Train recording and launch engines (running, walking and strength) while improving training plans.
- Preserve working behavior; prefer incremental, reversible changes with fast launch, scrolling and rendering.
- TestFlight uploads require an explicit user request for the active build.
