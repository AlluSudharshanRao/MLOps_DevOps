# DevOps Docs Guide (Read This First)

Use this guide to navigate DevOps documentation without overlap/confusion.

## Recommended reading order

1. `FLOW_start_to_current.md`
   - End-to-end timeline from start to current state.
   - Best first read for graders/teammates.

2. `EXPLANATION_so_far.md`
   - Why design and implementation decisions were made.
   - Root-cause/fix rationale and engineering tradeoffs.

3. `COMMANDS_history_and_explanations.md`
   - Command-first log of what was run, including troubleshooting commands.
   - Best for reproduction from terminal history.

4. `RUNBOOK_chameleon_k8s_zulip.md`
   - Historical deep dive of early Terraform/network bring-up.
   - Kept for detailed context and lessons learned.

5. `infrastructure-requirements.md`
   - Right-sizing/evidence table and final operational measurements.

## Scope note

The first four docs intentionally overlap slightly:
- `FLOW` answers **what happened and in what order**.
- `EXPLANATION` answers **why it was done this way**.
- `COMMANDS` answers **exactly what to run**.
- `RUNBOOK` preserves **historical low-level context** from early infra bring-up.

Current status should be treated as authoritative in:
- `FLOW_start_to_current.md`
- `EXPLANATION_so_far.md`
- `infrastructure-requirements.md`
