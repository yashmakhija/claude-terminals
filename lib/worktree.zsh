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

local _now; _now=$(date '+%H:%M')

{
  if [[ "$_goal_mode" == "diff" ]]; then
    printf "# Parallel Work Session\n"
  else
    printf "# %s\n" "${_goals[1]}"
  fi
  printf "_Started: %s — %d agents_\n\n" "$_now" "$n"

  # Agent Status — live heartbeat table
  printf "## Agent Status\n\n"
  printf "| Agent | Status | Current Task | Notes |\n"
  printf "|-------|--------|--------------|-------|\n"
  for i in $(seq 1 "$n"); do
    if [[ $i -eq 1 ]]; then
      printf "| Agent %d (lead) | ⏳ starting | planning | |\n" "$i"
    else
      printf "| Agent %d | ⏳ waiting | waiting for TASKS | |\n" "$i"
    fi
  done

  printf "\n---\n\n"

  # Task board
  printf "## Task Board\n\n"
  if [[ "$_goal_mode" == "diff" ]]; then
    printf "| # | Task | Agent | Phase | Status | Notes |\n"
    printf "|---|------|-------|-------|--------|-------|\n"
    for i in $(seq 1 "$n"); do
      printf "| %d | %s | | 1 | ⏳ pending | |\n" "$i" "${_goals[$i]}"
    done
  else
    printf "| # | Task | Agent | Phase | Status | Notes |\n"
    printf "|---|------|-------|-------|--------|-------|\n"
    printf "| - | _(Agent 1 fills this in after reading the codebase)_ | | | | |\n"
  fi

  printf "\n---\n\n"

  # Shared memory — all agents read and write here
  printf "## Shared Memory\n\n"
  printf "> Key decisions, findings, and context all agents need to know.\n"
  printf "> Any agent can add here — write enough for another agent to pick up your work.\n\n"
  printf "_(empty — agents will populate this as they work)_\n\n"

  printf "---\n\n"

  # Blockers
  printf "## Blockers\n\n"
  printf "_(none yet)_\n\n"

  printf "---\n\n"

  # Protocol
  printf "## Collaboration Rules\n\n"
  printf "1. **Before every action:** re-read this file to see what others are doing\n"
  printf "2. **Update Agent Status** every time you start or finish a subtask\n"
  printf "3. **Write to Shared Memory** any finding that another agent might need\n"
  printf "4. **Post to Blockers** if you're stuck — another agent may unblock you\n"
  printf "5. Status flow: ⏳ pending → 🔄 in progress → ✅ done → 🚫 blocked\n"
  printf "6. Save after every update — this file is the live memory shared by all agents\n"
} > "$main_dir/TASKS.md"

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
  printf "## Active Work Session (%d agents)\n\n" "$n"
  printf "\`TASKS.md\` is the shared live memory for this session — read it before every action, write back after every subtask.\n\n"
  printf "| Section | Purpose |\n"
  printf "|---------|--------|\n"
  printf "| Agent Status | Who is doing what right now — update your row constantly |\n"
  printf "| Task Board | All tasks and their phases — claim rows, update status |\n"
  printf "| Shared Memory | Findings, decisions, context — write anything another agent needs |\n"
  printf "| Blockers | Post when stuck; check if you can unblock others |\n\n"
  printf "Your code changes stay on your branch (\`work/agent-N\`). Merge when done.\n"
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
    sys_prompt="You are Agent 1 (lead) of ${n} in a parallel work session. Goal: ${goal}.

TASKS.md is your shared live memory — all agents read and write it. It syncs in real-time.

Your first move:
1. Read the codebase to understand the project
2. Break the goal into subtasks in TASKS.md (Task Board section), one row per agent
3. Update your row in Agent Status to show what you're doing
4. Write any key findings to Shared Memory so other agents can start
5. Claim task 1 and start working

Before every action: re-read TASKS.md. After every subtask: update your Agent Status row and add findings to Shared Memory. Post to Blockers if stuck. Save the file — it is the live coordination layer."
  else
    sys_prompt="You are Agent ${i} of ${n} in a parallel work session. Goal: ${goal}.

TASKS.md is your shared live memory — all agents read and write it. It syncs in real-time.

Your first move:
1. Read TASKS.md — wait for Agent 1 to fill the Task Board if it is empty
2. Claim an available task: put ${i} in the Agent column, change status to 🔄 in progress
3. Update your row in Agent Status
4. Work on your task; write key findings to Shared Memory as you go
5. When done, mark ✅ done and pick the next unclaimed task

Before every action: re-read TASKS.md. After every subtask: update Agent Status and Shared Memory. Post to Blockers if stuck. Save the file — it is the live coordination layer."
  fi

  _cmds+=("cd $(printf '%q' "$wt") && claude -n $(printf '%q' "Agent ${i}: ${goal}") --append-system-prompt $(printf '%q' "$sys_prompt")")
done

echo ""
echo "→ Opening ${n} terminals (Agent Teams: on)"
echo ""

source "${${(%):-%x}:A:h}/splits.zsh"
