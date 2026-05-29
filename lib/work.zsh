#!/usr/bin/env zsh
# c work [N] [--refresh]
# Opens N terminals in the current directory.
# Agent 1 is the orchestrator — user types their goal there.
# Agents 2-N watch TASKS.md and pick up tasks automatically.

dir="$PWD"
main_dir="$dir"

# ── flags ─────────────────────────────────────────────────────────────────────

local _refresh=0
local _n_arg=""
for arg in "$@"; do
  [[ "$arg" == "--refresh" ]] && _refresh=1
  [[ "$arg" =~ '^[0-9]+$' ]] && _n_arg="$arg"
done

# ── project context (auto-updates when git HEAD changes) ─────────────────────

local _ctx_file="$main_dir/CONTEXT.md"
local _current_sha=""
local _cached_sha=""
local _ctx=""

# Try git SHA for cache invalidation (works outside git too — just skips cache)
if git -C "$dir" rev-parse --git-dir &>/dev/null 2>&1; then
  _current_sha=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
  _cached_sha=$(grep -m1 'context-sha:' "$_ctx_file" 2>/dev/null | grep -o '[a-f0-9]\{7,\}')
fi

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

# ── how many terminals ────────────────────────────────────────────────────────

if [[ -n "$_n_arg" ]]; then
  n="$_n_arg"
else
  printf "How many agents? [2-8, default 4]: "
  read -r _n_input
  n="${_n_input:-4}"
fi
[[ "$n" =~ '^[2-9]$' || "$n" =~ '^[1-9][0-9]$' ]] || n=4

# ── TASKS.md ──────────────────────────────────────────────────────────────────

local _now; _now=$(date '+%H:%M')

{
  printf "# Work Session — %d agents\n" "$n"
  printf "_Started: %s_\n\n" "$_now"
  printf "## How it works\n\n"
  printf "Agent 1 is your orchestrator — type your goal there and it will coordinate the team.\n"
  printf "Agents 2-%d: watch this file — your task will appear here shortly.\n\n" "$n"

  printf "---\n\n"

  printf "## Task Board\n\n"
  printf "| # | Task | Agent | Files | Status | Notes |\n"
  printf "|---|------|-------|-------|--------|-------|\n"
  printf "| — | _(Agent 1 will fill this after receiving the goal)_ | | | | |\n\n"

  printf "---\n\n"

  printf "## Agent Status\n\n"
  printf "| Agent | Status | Notes |\n"
  printf "|-------|--------|-------|\n"
  printf "| Agent 1 (orchestrator) | ⏳ waiting for goal | |\n"
  for i in $(seq 2 "$n"); do
    printf "| Agent %d | ⏳ waiting for task assignment | |\n" "$i"
  done

  printf "\n---\n\n"

  printf "## Shared Memory\n\n"
  printf "> Agent 1 writes here before others start — key context, decisions, file structure.\n\n"
  printf "_(empty)_\n\n"

  printf "---\n\n"

  printf "## Blockers\n\n"
  printf "_(none yet)_\n"
} > "$main_dir/TASKS.md"

echo "✓ TASKS.md created"

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
  printf "**Agent 1** is the orchestrator — it receives the goal and assigns tasks.\n"
  printf "**Agents 2-%d** watch \`TASKS.md\` and pick up their assigned task.\n\n" "$n"
  printf "All agents work in the same directory on the same branch.\n"
  printf "<!-- /claude-work-session -->\n"
} >> "$claude_md"
echo "✓ CLAUDE.md updated"

# ── per-pane commands ─────────────────────────────────────────────────────────

export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

local _ctx_block=""
if [[ -n "$_ctx" ]]; then
  _ctx_block="## Project Context
${_ctx}

You do NOT need to explore the codebase — the above is a complete orientation.

---
"
fi

typeset -a _dirs _cmds

for i in $(seq 1 "$n"); do
  _dirs+=("$dir")
  local sys_prompt

  if [[ $i -eq 1 ]]; then
    sys_prompt="${_ctx_block}You are Agent 1 — the lead orchestrator of a ${n}-agent team working in the same project directory.

Agents 2-${n} are open in other terminals right now, watching TASKS.md for their assignments.

When the user gives you a goal:
1. Think through what needs to be built
2. Break it into exactly ${n} tasks — one per agent (including task 1 for yourself)
3. Write the Task Board in TASKS.md immediately — agents start as soon as they see it:

   | # | Task | Agent | Files | Status | Notes |
   Use real file paths. Assign files so NO two agents touch the same file.

4. Write to Shared Memory anything agents need to know (architecture decisions, conventions, key files)
5. Update Agent 1's status to 🔄 in progress
6. Start your own task

Be fast — the other agents are waiting. Write TASKS.md before doing anything else."

  else
    sys_prompt="${_ctx_block}You are Agent ${i} of ${n}. Agent 1 is the orchestrator and will assign your task.

Your job right now: watch TASKS.md. Agent 1 is writing your task assignment there.

When your row appears in the Task Board:
1. Read your assigned task and which files you own
2. Update your row status to 🔄 in progress and your Agent Status row
3. Start working immediately — stay within your assigned files
4. Write key findings to Shared Memory as you go
5. Post to Blockers if stuck

TASKS.md is the live coordination layer — re-read it before every action.
Do NOT start coding until Agent 1 has written your task to TASKS.md."
  fi

  local _pscript="/tmp/c-$$-${i}"
  printf '#!/usr/bin/env zsh\nprintf "\\033[2J\\033[H"\ncd %s && exec claude -n %s --append-system-prompt %s\n' \
    "$(printf '%q' "$dir")" \
    "$(printf '%q' "Agent ${i}$([ $i -eq 1 ] && echo ' (orchestrator)' || echo '')")" \
    "$(printf '%q' "$sys_prompt")" > "$_pscript"
  chmod +x "$_pscript"
  _cmds+=("$_pscript")
done

echo ""
printf "→ Opening %d terminals\n" "$n"
printf "\n  Agent 1 is your orchestrator — type your goal there.\n"
printf "  Agents 2-%d are waiting for task assignments.\n\n" "$n"

source "${${(%):-%x}:A:h}/splits.zsh"
