#!/bin/bash
# Hook to block auto-compaction when running under Ralph orchestrator
# When context fills up, this blocks compaction and exits the session
# Claude should have already been updating progress.txt throughout

# Read the JSON input from stdin
input=$(cat)

# Check if this is auto-triggered compaction
trigger=$(echo "$input" | jq -r '.trigger')

# Only block if CLAUDE_EXIT_ON_COMPACT env var is set AND it's auto-compact
if [[ "$CLAUDE_EXIT_ON_COMPACT" == "true" && "$trigger" == "auto" ]]; then
    # Exit code 2 blocks the action and ends the session
    exit 2
fi

# Otherwise allow compaction to proceed
exit 0
