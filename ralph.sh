#!/bin/bash
set -e

# Ralph Orchestrator - Autonomous AI Agent Loop
# Repeatedly calls Claude Code to work through tasks in prd.json

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Where ralph.sh lives
WORK_DIR="$(pwd)"  # Where user invoked ralph (the repo to work on)

# Configuration with defaults
MAX_ITERATIONS=${MAX_ITERATIONS:-10}
PROMPT_FILE=${PROMPT_FILE:-"$SCRIPT_DIR/prompt.md"}  # Default prompt from ralph install
BACKGROUND=${BACKGROUND:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[ralph]${NC} $1"; }
warn() { echo -e "${YELLOW}[ralph]${NC} $1"; }
error() { echo -e "${RED}[ralph]${NC} $1"; }
info() { echo -e "${BLUE}[ralph]${NC} $1"; }

# Initialize state files in WORK_DIR if they don't exist
init_state() {
    if [[ ! -f "$WORK_DIR/prd.json" ]]; then
        if [[ -f "$SCRIPT_DIR/prd.template.json" ]]; then
            cp "$SCRIPT_DIR/prd.template.json" "$WORK_DIR/prd.json"
            log "Created prd.json from template - edit it to add your tasks"
        else
            echo '{"project": "Unnamed Project", "stories": []}' > "$WORK_DIR/prd.json"
            log "Created empty prd.json - add your tasks before running"
        fi
    fi
    if [[ ! -f "$WORK_DIR/progress.txt" ]]; then
        echo "# Progress Log - $(date)" > "$WORK_DIR/progress.txt"
        echo "" >> "$WORK_DIR/progress.txt"
        log "Created progress.txt"
    fi
}

# Check if all tasks are complete
all_complete() {
    # If no stories exist, consider it not complete (need to add tasks first)
    if command -v jq &> /dev/null; then
        local total=$(jq '.stories | length' "$WORK_DIR/prd.json")
        if [[ "$total" -eq 0 ]]; then
            return 1
        fi
        local incomplete=$(jq '[.stories[] | select(.status != "done")] | length' "$WORK_DIR/prd.json")
        [[ "$incomplete" -eq 0 ]]
    else
        # Fallback without jq - check for any non-done statuses
        if ! grep -q '"stories"' "$WORK_DIR/prd.json"; then
            return 1
        fi
        grep -q '"status": "done"' "$WORK_DIR/prd.json" && \
        ! grep -qE '"status":\s*"(in_progress|pending|tested)"' "$WORK_DIR/prd.json"
    fi
}

# Check for COMPLETE signal in progress.txt
is_complete_signaled() {
    grep -q "^COMPLETE$" "$WORK_DIR/progress.txt" 2>/dev/null
}

# Main loop
run_loop() {
    init_state

    log "Starting Ralph orchestrator"
    info "Max iterations: $MAX_ITERATIONS"
    info "Prompt file: $PROMPT_FILE"
    info "Working directory: $WORK_DIR"
    echo ""

    for i in $(seq 1 $MAX_ITERATIONS); do
        log "=== Iteration $i of $MAX_ITERATIONS ==="
        echo ""

        # Check if complete signal was written
        if is_complete_signaled; then
            log "COMPLETE signal found in progress.txt"
            log "All tasks complete! Finished in $i iterations."
            exit 0
        fi

        # Check if all tasks are done
        if all_complete; then
            log "All tasks in prd.json are done!"
            exit 0
        fi

        # Ensure prompt file exists
        if [[ ! -f "$PROMPT_FILE" ]]; then
            error "Prompt file not found: $PROMPT_FILE"
            exit 1
        fi

        # Run Claude with the prompt
        log "Starting Claude session..."

        # Stay in work directory - Claude runs from the repo
        cd "$WORK_DIR"

        # Set env var to trigger context-full exit via PreCompact hook
        export CLAUDE_EXIT_ON_COMPACT=true

        # Run Claude and capture output
        # Exit code 2 = context full (hook blocked compaction), which is expected
        set +e
        claude --print "$(cat "$PROMPT_FILE")" 2>&1 | tee -a "$WORK_DIR/ralph.log"
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 ]]; then
            log "Claude session completed normally"
        elif [[ $exit_code -eq 2 ]]; then
            log "Claude session ended - context window full"
        else
            warn "Claude session exited with code $exit_code"
        fi

        echo ""
        log "Iteration $i complete"
        echo ""

        # Brief pause between iterations
        sleep 2
    done

    warn "Max iterations ($MAX_ITERATIONS) reached without completion"
    exit 1
}

# Background execution with caffeinate
run_background() {
    log "Starting background execution..."
    info "System will stay awake, display will sleep after 60 seconds"
    echo ""

    # Start caffeinate in background to prevent system sleep
    # -i: prevent idle sleep
    # -w $$: wait for this script's PID
    caffeinate -i -w $$ &
    CAFFEINATE_PID=$!

    # Sleep the display after 60 seconds to save power
    (sleep 60 && pmset displaysleepnow 2>/dev/null) &
    DISPLAY_SLEEP_PID=$!

    # Trap to cleanup on exit
    cleanup() {
        kill $CAFFEINATE_PID 2>/dev/null || true
        kill $DISPLAY_SLEEP_PID 2>/dev/null || true
    }
    trap cleanup EXIT

    # Run the main loop
    run_loop
}

# Show help
show_help() {
    echo "Ralph Orchestrator - Autonomous AI Agent Loop"
    echo ""
    echo "Usage: ralph [OPTIONS]"
    echo ""
    echo "Run from any git repository. Ralph will work in the current directory."
    echo ""
    echo "Options:"
    echo "  -n, --max-iterations N   Maximum iterations (default: 10)"
    echo "  -p, --prompt FILE        Custom prompt file (default: built-in prompt.md)"
    echo "  -b, --background         Run with caffeinate, sleep display"
    echo "  -h, --help               Show this help"
    echo ""
    echo "State Files (created in current directory):"
    echo "  prd.json      - Task list with statuses"
    echo "  progress.txt  - Append-only log of learnings"
    echo "  ralph.log     - Full output log from all iterations"
    echo ""
    echo "Quick Start:"
    echo "  1. cd into your repo"
    echo "  2. Run 'ralph' - it will create prd.json from template"
    echo "  3. Edit prd.json to define your tasks"
    echo "  4. Run 'ralph' again to start working"
    echo ""
    echo "Examples:"
    echo "  ralph                     # Run with defaults (10 iterations)"
    echo "  ralph -n 20               # Run up to 20 iterations"
    echo "  ralph -n 50 -b            # Background mode, 50 iterations"
    echo "  ralph -p ./my-prompt.md   # Use custom prompt file"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--max-iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        -p|--prompt)
            PROMPT_FILE="$2"
            shift 2
            ;;
        -b|--background)
            BACKGROUND=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

# Validate MAX_ITERATIONS is a number
if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    error "Max iterations must be a positive number"
    exit 1
fi

# Run
if [[ "$BACKGROUND" == "true" ]]; then
    run_background
else
    run_loop
fi
