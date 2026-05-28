#!/usr/bin/env zsh
# Shared split infrastructure — cmux, Ghostty, tmux fallback.
# Expects: n, _cmds[], _dirs[] set by caller.

# 2-column grid layout
_right=$(( n / 2 ))
_left=$(( n - _right ))

# ── 1. cmux ───────────────────────────────────────────────────────────────────

_cmux_bin() {
  local b="/Applications/cmux.app/Contents/Resources/bin/cmux"
  [[ -x "$b" ]] && { echo "$b"; return; }
  command -v cmux 2>/dev/null
}
CMUX_BIN=$(_cmux_bin)

if [[ -n "$CMUX_SURFACE_ID" && -n "$CMUX_BIN" ]] && "$CMUX_BIN" ping &>/dev/null; then
  _csplit() { local out; out=$("$CMUX_BIN" new-split "$1" --surface "$2" 2>&1); echo "$out" | grep -o 'surface:[0-9]*'; }
  _csend()  { "$CMUX_BIN" send --surface "$1" "${2}\n" 2>/dev/null; }

  my="$CMUX_SURFACE_ID"
  typeset -a right_surfs left_extra

  if (( _right >= 1 )); then
    sleep 0.2; right_surfs+=( "$(_csplit right "$my")" )
    for i in $(seq 2 $_right); do
      sleep 0.2; right_surfs+=( "$(_csplit down "${right_surfs[-1]}")" )
    done
  fi
  local last="$my"
  for i in $(seq 2 $_left); do
    sleep 0.2; local s; s=$(_csplit down "$last"); left_extra+=("$s"); last="$s"
  done

  "$CMUX_BIN" workspace-action --action equalize_splits 2>/dev/null
  sleep 0.5

  for k in $(seq 1 ${#right_surfs[@]}); do _csend "${right_surfs[$k]}" "${_cmds[$(( 2*k ))]}"; done
  for k in $(seq 1 ${#left_extra[@]}); do _csend "${left_extra[$k]}" "${_cmds[$(( 2*k+1 ))]}"; done
  _csend "$my" "${_cmds[1]}"
  exit 0
fi

# ── 2. Ghostty ────────────────────────────────────────────────────────────────

_ghostty_windows=$(osascript -e 'tell application "Ghostty" to count windows' 2>&1)

if [[ "$_ghostty_windows" =~ ^[0-9]+$ && "$_ghostty_windows" -gt 0 ]]; then
  _gcmd() {
    printf '  input text (%s & return) to %s\n' \
      "$(printf '"%s"' "${_cmds[$1]//\"/\\\"}")" "$2"
  }

  as_splits=""
  if (( _right >= 1 )); then
    as_splits+="  set tR1 to split myT direction right\n$(_gcmd 2 tR1)\n"
    local prev="tR1"
    for i in $(seq 2 $_right); do
      local v="tR${i}"
      as_splits+="  set $v to split $prev direction down\n$(_gcmd $(( 2*i )) $v)\n"
      prev="$v"
    done
  fi
  local prev="myT"
  for i in $(seq 2 $_left); do
    local v="tL${i}"
    as_splits+="  set $v to split $prev direction down\n$(_gcmd $(( 2*i-1 )) $v)\n"
    prev="$v"
  done

  result=$(osascript 2>&1 << ASEOF
tell application "Ghostty"
  try
    set myT to focused terminal of selected tab of front window
$(printf "%b" "$as_splits")
    perform action "equalize_splits" on myT
    input text ("${_cmds[1]//\"/\\\"}" & return) to myT
    return "ok"
  on error msg
    return "error:" & msg
  end try
end tell
ASEOF
  )

  if [[ "$result" == "ok" ]]; then exit 0; fi
  echo "Ghostty failed: $result — falling back to tmux..."
fi

# ── 3. tmux ───────────────────────────────────────────────────────────────────

if ! command -v tmux &>/dev/null; then echo "Error: brew install tmux"; exit 1; fi

_tmux_conf="$HOME/.config/claude-terminals/tmux.conf"
_tmux_sock="claude-terminals"
_tmux() { tmux -L "$_tmux_sock" -f "$_tmux_conf" "$@"; }

session="$(basename "${_dirs[1]}")-$$"

if [[ -n "$TMUX" ]]; then
  # Pass commands directly — nothing gets typed into the terminal
  for i in $(seq 2 "$n"); do tmux split-window -c "${_dirs[$i]}" "${_cmds[$i]}"; done
  tmux select-layout tiled
  exec "${_cmds[1]}"
fi

# New dedicated tmux session — commands passed directly, no send-keys
_tmux new-session -d -s "$session" -c "${_dirs[1]}" "${_cmds[1]}"
for i in $(seq 2 "$n"); do _tmux split-window -t "${session}:1" -c "${_dirs[$i]}" "${_cmds[$i]}"; done
_tmux select-layout -t "${session}:1" tiled
exec tmux -L "$_tmux_sock" -f "$_tmux_conf" attach-session -t "$session"
