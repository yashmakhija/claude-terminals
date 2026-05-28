#!/usr/bin/env zsh
# c worktree [--refresh]
# Interactive parallel work session — each agent gets its own git worktree,
# launched via native Claude Code flags (-n, --append-system-prompt).

dir="$PWD"
main_dir="$dir"

if ! git -C "$dir" rev-parse --git-dir &>/dev/null; then
  echo "Error: c worktree must be run from inside a git project."
  exit 1
fi

# ── flags ─────────────────────────────────────────────────────────────────────

local _refresh=0
for arg in "$@"; do [[ "$arg" == "--refresh" ]] && _refresh=1; done

# ── project context (auto-updates when git HEAD changes) ─────────────────────

local _ctx_file="$main_dir/CONTEXT.md"
local _current_sha; _current_sha=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
local _cached_sha; _cached_sha=$(grep -m1 'context-sha:' "$_ctx_file" 2>/dev/null | grep -o '[a-f0-9]\{7,\}')
local _ctx=""

if [[ $_refresh -eq 0 && -f "$_ctx_file" && -n "$_cached_sha" && "$_current_sha" == "$_cached_sha" ]]; then
  _ctx=$(grep -v '^<!-- context-sha:' "$_ctx_file")
  printf "  Project context up to date\n"
else
  printf "  Scanning project context..."

  local _ctx_prompt='Analyze this codebase and write a compact but complete project brief for coding agents about to start work.

Include all of these:
1. What this project does (1 sentence)
2. Tech stack: language version, framework, key libraries, database
3. How to run and test (exact commands from README or package.json/Makefile)
4. Key directories — name and purpose (5-8 max, use actual names)
5. Code patterns and conventions used in this codebase
6. Key files every agent must know about
7. Required env vars or external services (from .env.example or README)

Use markdown headers. Max 200 words. Use actual file and folder names from this project — be specific.'

  _ctx=$(cd "$dir" && claude --print "$_ctx_prompt" 2>/dev/null)
  if [[ -n "$_ctx" ]]; then
    {
      printf "<!-- context-sha: %s -->\n\n" "$_current_sha"
      printf '%s\n' "$_ctx"
    } > "$_ctx_file"
    printf " ✓\n"
  else
    printf " (skipped — Claude unavailable)\n"
  fi
fi

echo ""

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

  # Use context to generate codebase-specific task breakdown
  printf "\nPlanning %d tasks..." "$n"

  local _plan_prompt="You are planning parallel work for ${n} Claude Code agents on the same codebase.

Goal: ${_shared_goal}"

  [[ -n "$_ctx" ]] && _plan_prompt="${_plan_prompt}

Project context:
${_ctx}"

  _plan_prompt="${_plan_prompt}

Break this into exactly ${n} independent tasks agents can work on simultaneously.
Reference actual files and directories from the project context above.
Each task must be specific, actionable, and independently workable. Equal scope.

Return exactly ${n} lines. One task per line. No numbers, no bullets, no extra text."

  local _raw_plan
  _raw_plan=$(cd "$dir" && claude --print "$_plan_prompt" 2>/dev/null)

  if [[ -n "$_raw_plan" ]]; then
    local _line_count=0
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      (( _line_count++ ))
      (( _line_count > n )) && break
      _goals+=("$line")
    done <<< "$_raw_plan"

    while (( ${#_goals[@]} < n )); do _goals+=("$_shared_goal"); done

    printf " ✓\n\n"
    for i in $(seq 1 "$n"); do
      printf "  Agent %-2d → %s\n" "$i" "${_goals[$i]}"
    done
    printf "\n"

    printf "Proceed with these tasks? [y/n, default y]: "
    read -r _confirm
    if [[ "$_confirm" == "n" || "$_confirm" == "no" ]]; then
      _goals=()
      for i in $(seq 1 "$n"); do _goals+=("$_shared_goal"); done
      printf "Using shared goal for all agents.\n"
    fi
  else
    printf " (Claude unavailable, all agents share the same goal)\n"
    for i in $(seq 1 "$n"); do _goals+=("$_shared_goal"); done
  fi
fi

echo ""

# ── worktrees ─────────────────────────────────────────────────────────────────

local proj; proj=$(basename "$dir")
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

  printf "## Agent Status\n\n"
  printf "| Agent | Status | Current Task | Notes |\n"
  printf "|-------|--------|--------------|-------|\n"
  for i in $(seq 1 "$n"); do
    printf "| Agent %d | ⏳ ready | %s | |\n" "$i" "${_goals[$i]}"
  done

  printf "\n---\n\n"

  printf "## Task Board\n\n"
  printf "| # | Task | Agent | Phase | Status | Notes |\n"
  printf "|---|------|-------|-------|--------|-------|\n"
  for i in $(seq 1 "$n"); do
    printf "| %d | %s | %d | 1 | ⏳ pending | |\n" "$i" "${_goals[$i]}" "$i"
  done

  printf "\n---\n\n"

  printf "## Shared Memory\n\n"
  printf "> Key decisions, findings, and context all agents need to know.\n"
  printf "> Any agent can add here — write enough for another agent to pick up your work.\n\n"
  printf "_(empty — agents will populate this as they work)_\n\n"

  printf "---\n\n"

  printf "## Blockers\n\n"
  printf "_(none yet)_\n\n"

  printf "---\n\n"

  printf "## Collaboration Rules\n\n"
  printf "1. **Before every action:** re-read this file to see what others are doing\n"
  printf "2. **Update Agent Status** every time you start or finish a subtask\n"
  printf "3. **Write to Shared Memory** any finding that another agent might need\n"
  printf "4. **Post to Blockers** if you're stuck — another agent may unblock you\n"
  printf "5. Status flow: ⏳ pending → 🔄 in progress → ✅ done → 🚫 blocked\n"
  printf "6. Save after every update — this file is the live memory shared by all agents\n"
} > "$main_dir/TASKS.md"

for i in $(seq 1 "$n"); do
  ln -sf "$main_dir/TASKS.md"   "${_dirs[$i]}/TASKS.md"   2>/dev/null || true
  [[ -f "$_ctx_file" ]] && ln -sf "$_ctx_file" "${_dirs[$i]}/CONTEXT.md" 2>/dev/null || true
done
echo "✓ TASKS.md + CONTEXT.md symlinked into each worktree"

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

  if [[ -n "$_ctx" ]]; then
    printf "### Project Context\n\n%s\n\n---\n\n" "$_ctx"
  fi

  printf "\`TASKS.md\` is the shared live memory for this session — read it before every action, write back after every subtask.\n\n"
  printf "| Section | Purpose |\n"
  printf "|---------|--------|\n"
  printf "| Agent Status | Who is doing what right now — update your row constantly |\n"
  printf "| Task Board | All tasks and phases — update status as you work |\n"
  printf "| Shared Memory | Findings, decisions — write anything another agent needs |\n"
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

# Context block prepended to every agent's system prompt
local _ctx_block=""
if [[ -n "$_ctx" ]]; then
  _ctx_block="## Project Context
${_ctx}

You do NOT need to explore the codebase — the above is a complete orientation. Start your task immediately.

---
"
fi

for i in $(seq 1 "$n"); do
  local wt="${_dirs[$i]}"
  local goal="${_goals[$i]}"
  local sys_prompt

  sys_prompt="${_ctx_block}You are Agent ${i} of ${n} in a parallel work session. Your task: ${goal}.

TASKS.md is the shared live memory — all agents read and write it in real-time.

Your first move:
1. Update your row in Agent Status to 🔄 in progress
2. Start your task immediately — no codebase exploration needed, context is above
3. Write key findings to Shared Memory as you go

Before every action: re-read TASKS.md. After every subtask: update Agent Status and Shared Memory. Post to Blockers if stuck."

  # Write claude invocation to a temp script so terminals only see a short path,
  # not the full --append-system-prompt content being typed character by character.
  local _pscript="/tmp/c-$$-${i}"
  printf '#!/usr/bin/env zsh\ncd %s && exec claude -n %s --append-system-prompt %s\n' \
    "$(printf '%q' "$wt")" \
    "$(printf '%q' "Agent ${i}: ${goal}")" \
    "$(printf '%q' "$sys_prompt")" > "$_pscript"
  chmod +x "$_pscript"
  _cmds+=("$_pscript")
done

echo ""
echo "→ Opening ${n} terminals (Agent Teams: on)"
echo ""

source "${${(%):-%x}:A:h}/splits.zsh"
