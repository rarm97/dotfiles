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
| `S` | Source tmux.conf |
| `f` | Sessionizer popup |
| `w` | Session/window tree overview |
| `Backspace` | Clear screen and scrollback |

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
