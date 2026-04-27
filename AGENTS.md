# AGENTS.md — pi-nvim development notes

## Runtime & Tooling

- **Package manager**: Use `bun` for all package operations (`bun install`, `bun add`, etc.)
- **Script runner**: Use `bun run <script>` — not `make` in workflows
- **Test runner**: Uses Makefile under the hood ( delegates to `nvim --headless`)

We use **plenary.nvim** for automated tests.

### Running tests

```bash
make test
```

Which runs:
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"
```

### Test structure

| File | Purpose |
|---|---|
| `tests/minimal_init.lua` | Bootstraps plenary.nvim and sets up rtp |
| `tests/pi_split_spec.lua` | Tests for `:PiSplit` |

Tests run **headlessly** (no UI). They must be deterministic:
1. `before_each` wipes buffers and resets window layout
2. Assertions use plenary's `assert.equals` helpers

### Plenary bootstrap

`minimal_init.lua` clones `plenary.nvim` on first run to:
```
~/.local/share/nvim/site/pack/deps/start/plenary.nvim
```

To force a re-clone:
```bash
make clean-deps
```

## Commands

| Task | Command |
|------|---------|
| Run tests | `bun run test` |
| Clean deps | `bun run clean-deps` |
| Dry run release | `bun run release:dry` |
| Release (create PR) | See Git Workflow below |
| Session stats (all) | `./scripts/session-stats.sh` |
| Session stats (latest) | `./scripts/session-stats.sh --latest` |

> Users without bun can also use `make test` and `make clean-deps`.

## Conventions

- Lua-only, Neovim 0.11+ (may support earlier as features expand)
- No default keymaps; expose commands for users to bind
- `plugin/*.lua` for command/autocmd registration
- `lua/pi-nvim/` for implementation modules

## Git Workflow

The `main` branch is protected. **Never push directly to `main`.** Always create a feature branch and open a pull request.

### Branch naming

```
<type>/<short-description>-<model>
```

- `<type>`: conventional commit type (`feat`, `fix`, `refactor`, `chore`, etc.)
- `<short-description>`: brief hyphenated description
- `<model>`: the primary model that worked on the change (use the full model name from session stats, e.g. `minimax`, `claude`, `gemini`)

Examples:
- `feat/status-bar-timer-minimax`
- `fix/timer-leak-minimax`
- `chore/release-workflow-minimax`

### Creating a PR

```bash
# Create a feature branch
git checkout -b feat/status-bar-timer-minimax

# Make commits following conventional format, then:
git push -u origin feat/status-bar-timer-minimax

# Include session stats in the PR body:
./scripts/session-stats.sh --latest

gh pr create --title "feat: show running time in status bar" --body "$(cat <<'EOF'
## Summary

<describe the change>

## Session cost

<paste output of ./scripts/session-stats.sh --latest here>
EOF
)"
```

### PR description template

Every PR should include:

1. **Summary** — what changed and why
2. **Session cost** — paste the output of `./scripts/session-stats.sh --latest` (or `./scripts/session-stats.sh` for all sessions). This shows models used, token counts, and cost.

### Updating a PR

```bash
git add ...
git commit -m "fix: address review feedback"
git push
```

### Merging

After CI passes and review is approved, merge via:

```bash
gh pr merge --squash --delete-branch
```

## Versioning & Releases

This project uses [Conventional Commits](https://www.conventionalcommits.org/) with [standard-version](https://github.com/conventional-changelog/standard-version) for automated versioning and changelog generation.

### How releases work

Releases happen **automatically on every merge to `main`**. The CI workflow (`.github/workflows/release.yml`):

1. Detects a push to `main` (i.e., a PR merge)
2. Runs tests
3. Runs `standard-version` to bump the version and update `CHANGELOG.md`
4. Pushes the version bump commit and git tag to `main`
5. Creates a GitHub Release with changelog notes

The version bump depends on the commit messages in the merged PR:

| Commit type | Version bump |
|-------------|--------------|
| `feat` | minor (0.x.0) |
| `fix`, `refactor`, `perf` | patch (0.0.x) |
| `feat!` or `BREAKING CHANGE` | major (x.0.0) |
| `docs`, `chore`, `test` | none |

### Commit message format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Examples:

```bash
git commit -m "feat: add PiSplit command for splitting windows"
git commit -m "fix: resolve race condition in buffer cleanup"
git commit -m "feat!: remove deprecated check type"
git commit -m "docs: update installation instructions"
```

### Setup: RELEASE_TOKEN

The workflow pushes version bump commits back to the protected `main` branch, which requires a Personal Access Token (PAT) with write access that can bypass branch protections.

To set this up:

1. Create a fine-grained PAT with **Contents: Read and write** permission for this repo
2. Grant the PAT's user/account "Bypass branch protections" permission in **Settings → Branch protection rules → main**
3. Add the PAT as a repository secret named **`RELEASE_TOKEN`** in **Settings → Secrets and variables → Actions**

If `RELEASE_TOKEN` is not set, the workflow falls back to `GITHUB_TOKEN`, which may fail if `main` is protected.

### Manual release (rare)

If you need to trigger a release manually (e.g., to pick up missed commits):

```bash
git checkout main
git pull
git checkout -b chore/release
./scripts/release
git push -u origin chore/release
gh pr create --title "chore: release v$(node -p "require('./package.json').version")" --body "Manual version bump and changelog update.\n\n## Session cost\n\n$(./scripts/session-stats.sh --latest)"
# After merge, CI will handle tagging and GitHub Release
```

### Dry run

To preview what version bump and changelog will happen:

```bash
./scripts/release --dry-run
```

This runs `standard-version --dry-run` (no commits, no tags). The actual release happens automatically when PRs merge to `main` — see the Git Workflow section.

### Installation by version

Users can install a specific version via their plugin manager. For example, with `lazy.nvim`:

```lua
{ "garyjohnson/pi-nvim", version = "v0.1.0" }
```

Or pin to a commit:

```lua
{ "garyjohnson/pi-nvim", commit = "abc123" }
```