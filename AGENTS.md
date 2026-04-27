# AGENTS.md — pi-nvim development notes

## Testing

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

## Conventions

- Lua-only, Neovim 0.11+ (may support earlier as features expand)
- No default keymaps; expose commands for users to bind
- `plugin/*.lua` for command/autocmd registration
- `lua/pi-nvim/` for implementation modules
