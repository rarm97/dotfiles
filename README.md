# dotfiles

Personal development environment managed with [GNU Stow](https://www.gnu.org/software/stow/). Rosé Pine Moon theme across Neovim, tmux, WezTerm, and Starship.

## What's included

| Package | What it does |
|---------|-------------|
| **nvim** | Neovim config — LSP, Treesitter, Telescope, Harpoon, Git integration, completions, ThePrimeagen's 99 AI plugin |
| **tmux** | Window-focused workflow with vim-style navigation, session persistence via resurrect/continuum |
| **wezterm** | Terminal emulator — auto-attaches to tmux, Rosé Pine Moon theme, JetBrainsMono Nerd Font |
| **zsh** | Shell config — lazy NVM, cached completions, fzf integration, autosuggestions, syntax highlighting |
| **starship** | Minimal prompt — directory, git branch, git status |
| **git** | Global git config and ignores |
| **home** | Global formatter configs (.prettierrc, .stylua.toml, .clang-format) |

## Setup

```sh
# Full bootstrap (installs Homebrew, tools, and stows everything)
./bootstrap.sh

# Or just stow the configs
make stow
```

## Key tmux bindings

Prefix is `Ctrl-a`.

| Binding | Action |
|---------|--------|
| `h` / `l` | Previous / next window |
| `j` / `k` | Next / previous session |
| `c` | New window |
| `q` | Kill window (with confirmation) |
| `Q` | Kill session (smart — won't close WezTerm) |
| `r` / `R` | Rename window / session |
| `s` | Save session (resurrect) |
| `M-s` | Save session, bypassing the degenerate-state guard |
| `S` | Source tmux.conf |
| `f` | Sessionizer popup |
| `w` | Session/window tree overview |
| `Backspace` | Clear screen and scrollback |

## Session persistence

tmux-resurrect saves the session layout; tmux-continuum auto-saves every 15
minutes and auto-restores on tmux start. Saves live in
`~/.local/share/tmux/resurrect/`, and a `last` symlink points at the one that
auto-restore will use.

Two helper scripts in `tmux/.local/bin/` harden that setup:

**`tmux-resurrect-guard`** — stops a throwaway session state from becoming
`last`. Continuum saves on a timer, so if the timer fires while tmux is holding
something trivial (the bare one-window `main` session WezTerm creates on
startup, for instance) that trivial state would otherwise be written out and
`last` repointed at it — and the next auto-restore would faithfully bring back
one window instead of your real workspace.

It runs as resurrect's `post-save-layout` hook, which fires after the candidate
save is written but before `last` moves. It counts `window` records in the
candidate and vetoes the save if the state looks throwaway. Tuning options live
next to the plugin settings in `tmux.conf`; the mechanism is explained in the
script's header.

**`tmux-resurrect-saves`** — manages the save directory:

```sh
tmux-resurrect-saves list                # every save with session/window/pane counts
tmux-resurrect-saves prune               # dry run of the retention policy
tmux-resurrect-saves prune --apply       # actually delete
tmux-resurrect-saves promote <timestamp> # point `last` at a specific save
```

Retention keeps everything from the last 7 days, then one save per day back to
90 days, and drops degenerate saves at any age. Whatever `last` points at is
never deleted.

## Key Neovim bindings

Leader is `Space`.

| Binding | Action |
|---------|--------|
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>gs` | Git status (Fugitive) |
| `<leader>ca` | Code action |
| `<leader>rn` | Rename symbol |
| `gd` | Go to definition |
| `gr` | References |
| `]q` / `[q` | Next / prev quickfix item |
| `<leader>lq` | Send diagnostics to quickfix |
| `<leader>9s` | 99 AI search |
| `<leader>9v` | 99 AI visual replace |

## Make targets

```
make stow       # Apply symlinks (with dry-run)
make unstow     # Remove symlinks
make check      # Verify tools and config paths
make doctor     # Debug info (PATH, symlinks, etc.)
make bootstrap  # Full setup from scratch
```
