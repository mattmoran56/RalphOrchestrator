# Ralph Orchestrator

An autonomous AI agent loop that repeatedly calls Claude Code to work through tasks. Ralph gives Claude fresh context each iteration while persisting state in files, enabling long-running autonomous development sessions.

## The Philosophy: Iteration Over Perfection

Ralph implements a technique created by [Geoffrey Huntley](https://github.com/ghuntley) for autonomous software development. The original approach uses a deceptively simple mechanism:

```bash
while :; do cat PROMPT.md | claude ; done
```

This loop embodies a transformative principle: **repeated attempts succeed where single perfect attempts fail**. Rather than attempting flawless execution initially, the system persistently retries until achieving success.

Geoffrey Huntley describes this philosophy as being "deterministically bad in an undeterministic world"—meaning the system accepts imperfection as a starting point, knowing that sustained iteration will eventually converge toward working solutions.

## Why Fresh Context Matters

With Ralph, it's crucial that each iteration starts with a **completely fresh context window**—not compacted or summarized context.

**The Context Sweet Spot**: Claude performs best when context usage is between 0-50% of the total window. Above 50%, performance on complex tasks degrades significantly. By starting fresh each iteration, Ralph keeps Claude in this optimal zone.

**The Power of Persistence**: When Ralph gets stuck on a problem, it logs what it tried to `progress.txt`. The next iteration reads this log with fresh eyes and full context capacity. It knows what approaches failed, giving it the knowledge to be novel and try new things—while having the cognitive headroom to actually execute on those ideas.

This is the joy of Ralph: each iteration combines the **wisdom of past attempts** with the **full capability of fresh context**.

## How It Works

Ralph is a bash script that:

1. **Loops** - Repeatedly invokes Claude Code with the same prompt
2. **Persists state** - Uses `prd.json` for task tracking and `progress.txt` for learnings
3. **Handles context limits** - A PreCompact hook detects when context fills up and gracefully exits
4. **Supports background execution** - Uses `caffeinate` to prevent sleep during overnight runs

Each Claude session starts fresh with no memory of previous sessions. Claude reads `prd.json` and `progress.txt` at the start of each iteration to understand what's been done and what remains.

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/mattmoran56/RalphOrchestrator.git
cd RalphOrchestrator
```

### 2. Make the script executable

```bash
chmod +x ralph.sh
```

### 3. Add to your PATH

Create a symlink in a directory that's in your PATH:

```bash
# Create ~/bin if it doesn't exist
mkdir -p ~/bin

# Create symlink (run from the cloned repo directory)
ln -s "$(pwd)/ralph.sh" ~/bin/ralph
```

If `~/bin` isn't in your PATH, add it to your shell config:

```bash
# For zsh (~/.zshrc)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# For bash (~/.bashrc)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 4. Install the PreCompact hook

Copy the hook to your Claude settings:

```bash
# Create hooks directory
mkdir -p ~/.claude/hooks

# Copy the hook (run from the cloned repo directory)
cp hooks/no-auto-compact.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/no-auto-compact.sh
```

Add the hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/no-auto-compact.sh"
          }
        ]
      }
    ]
  }
}
```

## Usage

Run from any git repository:

```bash
cd /path/to/your/repo
ralph
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-n, --max-iterations N` | Maximum iterations before stopping | 10 |
| `-p, --prompt FILE` | Custom prompt file | Built-in prompt.md |
| `-b, --background` | Run with caffeinate, sleep display | false |
| `-h, --help` | Show help | - |

### Examples

```bash
# Basic run (10 iterations)
ralph

# Run up to 20 iterations
ralph -n 20

# Overnight background mode (50 iterations)
ralph -n 50 -b

# Use a custom prompt file
ralph -p ./my-project-prompt.md
```

## State Files

Ralph creates these files in your **current working directory** (the repo you're working in):

| File | Purpose | Git Status |
|------|---------|------------|
| `prd.json` | Structured task list with statuses | Should be gitignored |
| `progress.txt` | Append-only log of learnings | Should be gitignored |
| `ralph.log` | Full output from all iterations | Should be gitignored |

Add to your repo's `.gitignore`:

```
prd.json
progress.txt
ralph.log
```

## Task File: prd.json

When you first run Ralph, it creates `prd.json` from a template. Edit it to define your tasks:

```json
{
  "project": "My Project",
  "stories": [
    {
      "id": 1,
      "priority": 1,
      "title": "Implement user authentication",
      "description": "Add login/logout functionality",
      "status": "pending",
      "acceptance_criteria": [
        "Users can log in with email/password",
        "Sessions persist across page refreshes",
        "Logout clears session"
      ]
    },
    {
      "id": 2,
      "priority": 2,
      "title": "Add dashboard page",
      "description": "Create main dashboard after login",
      "status": "pending",
      "acceptance_criteria": [
        "Shows user's name",
        "Displays recent activity"
      ]
    }
  ]
}
```

**Status progression**: `pending` → `in_progress` → `tested` → `done`

## File Structure

```
RalphOrchestrator/           # This repo (install location)
├── ralph.sh                 # Main orchestrator script
├── prompt.md                # Default prompt for Claude
├── prd.template.json        # Template copied to new repos
├── hooks/
│   └── no-auto-compact.sh   # PreCompact hook (copy to ~/.claude/hooks/)
└── README.md                # This file

~/.claude/                   # Claude settings (after installation)
├── settings.json            # Claude settings with hook config
└── hooks/
    └── no-auto-compact.sh   # PreCompact hook
```

## How the Code Works

### ralph.sh

The main orchestrator:

1. **Directory handling**: Uses `SCRIPT_DIR` (where ralph.sh lives) for loading the prompt, and `WORK_DIR` (current directory) for state files and running Claude
2. **State initialization**: Copies `prd.template.json` to create `prd.json` if it doesn't exist
3. **Main loop**: Runs Claude with the prompt, capturing output to `ralph.log`
4. **Exit detection**: Checks for `COMPLETE` signal in `progress.txt` or all tasks marked `done`
5. **Background mode**: Uses `caffeinate -i` to prevent system sleep and `pmset displaysleepnow` to sleep the display

### prompt.md

Instructions given to Claude each iteration:

- Read state files first (no memory of previous sessions)
- Select highest-priority incomplete task
- Update task status as work progresses
- Commit frequently in small, logical units
- Update `progress.txt` regularly (not just at end)
- Never commit state files

### no-auto-compact.sh (PreCompact Hook)

Detects when Claude's context window is filling up:

```bash
# Only blocks when CLAUDE_EXIT_ON_COMPACT=true (set by ralph.sh)
# AND the trigger is "auto" (automatic compaction)
if [[ "$CLAUDE_EXIT_ON_COMPACT" == "true" && "$trigger" == "auto" ]]; then
    exit 2  # Exit code 2 blocks the action and ends session
fi
```

This allows Ralph to detect context limits and start a fresh session with full context.

## Completion

Ralph stops when:

1. All tasks in `prd.json` have status `"done"`
2. `progress.txt` contains a line with just `COMPLETE`
3. Maximum iterations is reached

## Troubleshooting

### Claude not picking up tasks

- Ensure `prd.json` has tasks with status other than `"done"`
- Check that the prompt is being loaded (ralph uses prompt.md from its install directory)

### Hook not working

- Verify hook is executable: `chmod +x ~/.claude/hooks/no-auto-compact.sh`
- Check `jq` is installed: `which jq`
- Verify settings.json has the hook configured

### Background mode issues

- Ensure `caffeinate` and `pmset` are available (macOS only)
- Check Activity Monitor to verify caffeinate is running

## Requirements

- macOS (for background mode with caffeinate/pmset)
- Claude Code CLI (`claude` command)
- `jq` (for JSON parsing in hook and completion check)
- Bash 4.0+
