#!/usr/bin/env zsh
# c terminal <N>
# Opens N panes with claude in each, all in the current directory.

n="${1:-4}"
dir="$PWD"
typeset -a _dirs _cmds

for i in $(seq 1 "$n"); do
  _dirs+=("$dir")
  _cmds+=("cd $(printf '%q' "$dir") && claude")
done

source "${${(%):-%x}:A:h}/splits.zsh"
