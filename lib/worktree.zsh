#!/usr/bin/env zsh
# c worktree
# Interactive parallel work session — each agent gets its own git worktree,
# launched via native Claude Code flags (-n, --append-system-prompt).

dir="$PWD"

if ! git -C "$dir" rev-parse --git-dir &>/dev/null; then
  echo "Error: c worktree must be run from inside a git project."
  exit 1
fi

# ── prompts ───────────────────────────────────────────────────────────────────

printf "How many terminals? [2-8, default 4]: "
read -r _n_input
n="${_n_input:-4}"
[[ "$n" =~ '^[2-9]$' || "$n" =~ '^[1-9][0-9]$' ]] || n=4

printf "Same goal for all, or different per terminal? [same/diff, default same]: "
read -r _goal_mode
_goal_mode="${_goal_mode:-same}"

typeset -a _goals

if [[ "$_goal_mode" == "diff" ]]; then
  for i in $(seq 1 "$n"); do
    printf "Goal for agent %d: " "$i"
    read -r _g
    [[ -z "$_g" ]] && { echo "Please provide a goal for agent $i."; exit 1; }
    _goals+=("$_g")
  done
else
  printf "What are you working on? "
  read -r _shared_goal
  [[ -z "$_shared_goal" ]] && { echo "Please describe the goal."; exit 1; }
  for i in $(seq 1 "$n"); do _goals+=("$_shared_goal"); done
fi

echo ""

# ── worktrees ─────────────────────────────────────────────────────────────────

local proj; proj=$(basename "$dir")
local main_dir="$dir"
local base_branch; base_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
typeset -a _dirs _cmds

for i in $(seq 1 "$n"); do
  local branch="work/agent-${i}"
  local wt="${dir%/*}/${proj}-agent-${i}"

  if [[ ! -d "$wt" ]]; then
    git -C "$dir" worktree add -b "$branch" "$wt" "$base_branch" 2>/dev/null || \
      git -C "$dir" worktree add "$wt" "$branch" 2>/dev/null
  fi
  _dirs+=("$wt")
  echo "✓ Worktree → $wt  (branch: $branch)"
done

# ── .worktreeinclude — auto-copy env files into each worktree ─────────────────

local wti="$main_dir/.worktreeinclude"
if [[ ! -f "$wti" ]]; then
  local env_files=()
  for f in .env .env.local .env.development .env.production .env.test; do
    [[ -f "$main_dir/$f" ]] && env_files+=("$f")
  done
  if (( ${#env_files[@]} > 0 )); then
    printf '%s\n' "${env_files[@]}" > "$wti"
    echo "✓ .worktreeinclude created (copies: ${env_files[*]})"
  fi
fi

# ── TASKS.md ──────────────────────────────────────────────────────────────────

if [[ "$_goal_mode" == "diff" ]]; then
  {
    printf "# Parallel Work Session\n\n"
    printf "## Tasks\n\n"
    printf "| # | Task | Agent | Status | Notes |\n"
    printf "|---|------|-------|--------|-------|\n"
    for i in $(seq 1 "$n"); do
      printf "| %d | %s | | ⏳ pending | |\n" "$i" "${_goals[$i]}"
    done
    printf "\n## Protocol\n"
    printf "- Claim your row: put your agent number in the Agent column\n"
    printf "- Status: ⏳ pending → 🔄 in progress → ✅ done\n"
    printf "- Commit: \`git add TASKS.md && git commit -m 'tasks: update'\`\n"
  } > "$main_dir/TASKS.md"
else
  {
    printf "# %s\n\n" "${_goals[1]}"
    printf "## Tasks\n\n"
    printf "| # | Task | Agent | Status | Notes |\n"
    printf "|---|------|-------|--------|-------|\n"
    printf "| - | *(agent 1 will fill this in)* | | | |\n\n"
    printf "## Protocol\n"
    printf "- **Agent 1 (lead):** reads the codebase, breaks the goal into subtasks above\n"
    printf "- **All agents:** claim a row, keep status updated\n"
    printf "- Status: ⏳ pending → 🔄 in progress → ✅ done\n"
    printf "- Commit: \`git add TASKS.md && git commit -m 'tasks: update'\`\n"
  } > "$main_dir/TASKS.md"
fi

for i in $(seq 1 "$n"); do
  ln -sf "$main_dir/TASKS.md" "${_dirs[$i]}/TASKS.md" 2>/dev/null || true
done
echo "✓ TASKS.md created + symlinked into each worktree"

# ── CLAUDE.md ─────────────────────────────────────────────────────────────────

local claude_md="$main_dir/CLAUDE.md"
if [[ -f "$claude_md" ]]; then
  awk '/<!-- claude-work-session -->/,/<!-- \/claude-work-session -->/{next} 1' \
    "$claude_md" > "${claude_md}.tmp" && mv "${claude_md}.tmp" "$claude_md"
  printf "\n" >> "$claude_md"
fi
{
  printf "<!-- claude-work-session -->\n"
  printf "## Active Work Session\n"
  printf "**Agents:** %d Claude instances, each on their own git branch\n\n" "$n"
  printf "Read \`TASKS.md\` to see all tasks. Claim one and keep it updated.\n"
  printf "Your changes stay on your branch — merge when done.\n"
  printf "<!-- /claude-work-session -->\n"
} >> "$claude_md"

for i in $(seq 1 "$n"); do
  ln -sf "$claude_md" "${_dirs[$i]}/CLAUDE.md" 2>/dev/null || true
done
echo "✓ CLAUDE.md updated"

# ── per-pane commands using native Claude Code flags ─────────────────────────

export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

for i in $(seq 1 "$n"); do
  local wt="${_dirs[$i]}"
  local goal="${_goals[$i]}"
  local sys_prompt

  if [[ $i -eq 1 ]]; then
    sys_prompt="Goal: ${goal}. You are Agent 1 (lead) of ${n} in a parallel work session. Read the codebase first, break the goal into subtasks in TASKS.md, claim task 1, and start working. Other agents are waiting for your TASKS.md update."
  else
    sys_prompt="Goal: ${goal}. You are Agent ${i} of ${n} in a parallel work session. Read TASKS.md, claim an available task (put your agent number in the Agent column), and work independently. Update status as you go."
  fi

  _cmds+=("cd $(printf '%q' "$wt") && claude -n $(printf '%q' "Agent ${i}: ${goal}") --append-system-prompt $(printf '%q' "$sys_prompt")")
done

echo ""
echo "→ Opening ${n} terminals (Agent Teams: on)"
echo ""

source "${${(%):-%x}:A:h}/splits.zsh"
