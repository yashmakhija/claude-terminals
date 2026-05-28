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

```bash
c worktree
```

Two prompts:

```
How many terminals? [2/3/4/6/8, default 4]: 4
What are you working on? Refactor auth system to use JWT
```

That's it. Four panes open. Every Claude shares the same goal via `TASKS.md` and `CLAUDE.md`.

**Agent 1 (top-left) is the lead** — it reads the codebase, breaks the goal into subtasks in `TASKS.md`, then starts on its piece. Agents 2–4 read `TASKS.md`, each claims a task, and works independently.

## Layout

```
┌──────────────┬──────────────┐
│   agent 1    │   agent 2    │
│   (lead)     │              │
├──────────────┼──────────────┤
│   agent 3    │   agent 4    │
│              │              │
└──────────────┴──────────────┘
```

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
