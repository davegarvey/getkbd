# Agent Development

## Concurrent Work

- Use a separate Git worktree and branch for each agent. Do not share a working directory between agents.
- Keep agent worktrees under `.worktrees/`, for example: `git worktree add .worktrees/<name> -b <branch-name>`.
