#!/usr/bin/env bash
set -e

echo "Installing claude-terminals..."

# Resolve source: local clone or remote download
if [[ -f "./bin/c" ]]; then
  SRC="./bin/c"
else
  TMP=$(mktemp)
  curl -fsSL "https://raw.githubusercontent.com/chiragmakhija/claude-terminals/main/bin/c" -o "$TMP"
  SRC="$TMP"
  CLEANUP=1
fi

# Install to ~/bin
mkdir -p "$HOME/bin"
cp "$SRC" "$HOME/bin/c"
chmod +x "$HOME/bin/c"
[[ -n "$CLEANUP" ]] && rm -f "$SRC"
echo "  Installed $HOME/bin/c"

# Install tmux config (mouse, Alt+arrow nav, status bar hints)
TMUX_CONF_DIR="$HOME/.config/claude-terminals"
TMUX_CONF="$TMUX_CONF_DIR/tmux.conf"
mkdir -p "$TMUX_CONF_DIR"
if [[ -f "./tmux.conf" ]]; then
  cp "./tmux.conf" "$TMUX_CONF"
else
  curl -fsSL "https://raw.githubusercontent.com/chiragmakhija/claude-terminals/main/tmux.conf" -o "$TMUX_CONF"
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
if [[ -f "$CLAUDE_SETTINGS" ]]; then
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
echo "  c terminal 4    # open 4 splits, claude in pane 1"
echo "  c terminal 2    # open 2 splits"
