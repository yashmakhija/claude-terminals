#!/usr/bin/env bash
set -e

REPO="https://raw.githubusercontent.com/chiragmakhija/claude-terminals/main"

echo "Installing claude-terminals..."

# Resolve source: local clone or remote download
if [[ -f "./bin/c" ]]; then
  LOCAL=1
else
  LOCAL=0
fi

# Install bin/c
mkdir -p "$HOME/bin"
if (( LOCAL )); then
  cp "./bin/c" "$HOME/bin/c"
else
  curl -fsSL "$REPO/bin/c" -o "$HOME/bin/c"
fi
chmod +x "$HOME/bin/c"
echo "  Installed $HOME/bin/c"

# Install lib/ scripts
LIB_DIR="$HOME/lib/claude-terminals"
mkdir -p "$LIB_DIR"
for f in terminal.zsh worktree.zsh work.zsh splits.zsh; do
  if (( LOCAL )); then
    cp "./lib/$f" "$LIB_DIR/$f"
  else
    curl -fsSL "$REPO/lib/$f" -o "$LIB_DIR/$f"
  fi
done
echo "  Installed $LIB_DIR/"

# Point bin/c at the installed lib/ location
# bin/c resolves lib relative to itself: ../lib — so we need a symlink
# or we patch the installed c to use an absolute lib path
sed -i '' "s|_LIB=\"\${_BIN}/../lib\"|_LIB=\"$LIB_DIR\"|" "$HOME/bin/c"

# Install tmux config
TMUX_CONF_DIR="$HOME/.config/claude-terminals"
TMUX_CONF="$TMUX_CONF_DIR/tmux.conf"
mkdir -p "$TMUX_CONF_DIR"
if (( LOCAL )); then
  cp "./tmux.conf" "$TMUX_CONF"
else
  curl -fsSL "$REPO/tmux.conf" -o "$TMUX_CONF"
fi
echo "  Installed $TMUX_CONF"

# Add ~/bin to PATH if not already there
SHELL_RC="$HOME/.zshrc"
[[ "$SHELL" == *bash* ]] && SHELL_RC="$HOME/.bashrc"

if ! grep -q '"$HOME/bin"' "$SHELL_RC" 2>/dev/null && \
   ! grep -qE '^export PATH.*\$HOME/bin' "$SHELL_RC" 2>/dev/null; then
  printf '\n# claude-terminals\nexport PATH="$HOME/bin:$PATH"\n' >> "$SHELL_RC"
  echo "  Added ~/bin to PATH in $SHELL_RC"
fi

# Optional: add Claude Code SessionStart hook
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -t 0 && -f "$CLAUDE_SETTINGS" ]]; then
  echo ""
  read -rp "Add SessionStart reminder hook to Claude Code? [y/N] " add_hook
  if [[ "$add_hook" =~ ^[Yy]$ ]]; then
    echo "  Add this to the 'hooks' section of $CLAUDE_SETTINGS:"
    cat <<'JSON'

  "SessionStart": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "if [[ -z \"$TMUX\" && -z \"$GHOSTTY_WINDOW_ID\" ]]; then echo 'Tip: Run `c terminal 4` inside Ghostty to set up your workspace'; fi"
        }
      ]
    }
  ]

JSON
  fi
fi

echo ""
echo "Done! Restart your shell or run:"
echo "  source $SHELL_RC"
echo ""
echo "Usage:"
echo "  c work 4        # 4 agents, Agent 1 orchestrates the team"
echo "  c terminal 4    # 4 bare Claude sessions"
echo "  c worktree      # parallel agents on separate git branches"
