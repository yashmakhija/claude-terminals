# claude-terminals

One command to open a multi-pane Claude Code workspace in your current directory.

```
c terminal 4
```

![claude-terminals preview](assets/preview.png)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/yashmakhija/claude-terminals/main/install.sh | bash
```

Then reload your shell:

```bash
source ~/.zshrc
```

## Usage

### Open N panes

```bash
c terminal 4    # 4 panes, claude in each
c terminal 2    # 2 panes
```

### Parallel work session

Assign each pane a task. A shared `TASKS.md` is created so every Claude can see the full picture and update status as it works.

```bash
c work "implement auth" "fix login bug" "write tests" "update docs"
```

Each pane shows a task banner and starts Claude. Claude reads `TASKS.md` automatically (via `CLAUDE.md`) and knows what all agents are working on.

### With git worktrees

Each task gets its own isolated branch — no file conflicts between agents.

```bash
c work --worktree "implement auth" "fix login bug" "write tests"
```

Creates `../project-wt-1/`, `../project-wt-2/`, `../project-wt-3/` — each on a separate branch derived from the task name. `TASKS.md` is symlinked into every worktree so all agents share the same status board.

## Layout

```
┌─────────────┬─────────────┐
│   task 1    │   task 2    │
├─────────────┼─────────────┤
│   task 3    │   task 4    │
└─────────────┴─────────────┘
```

Tasks are numbered in reading order. Each pane shows its assignment when it opens.

## Requirements

- **macOS + [Ghostty](https://ghostty.org)** — uses Ghostty's native splits via AppleScript
- **tmux** — fallback for any other terminal (`brew install tmux`)

For the tmux fallback, navigation is pre-configured — no tmux knowledge needed:

| Action | How |
|---|---|
| Switch pane | Click with mouse, or Alt+Arrow |
| Close pane | Ctrl+D |
| Resize pane | Ctrl+Alt+Arrow |

## How it works

1. **Inside Ghostty** — uses Ghostty's AppleScript API to create native splits. Each pane starts in your project directory with `claude` already running.
2. **Any other terminal** — creates a tmux session with mouse support and Alt+Arrow navigation built in.

## Claude Code hook (optional)

Shows a reminder tip when you open Claude outside a prepared workspace. Add to `~/.claude/settings.json`:

```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "if [[ -z \"$TMUX\" && -z \"$GHOSTTY_WINDOW_ID\" ]]; then echo 'Tip: Run `c terminal 4` to set up your workspace'; fi"
        }
      ]
    }
  ]
}
```
