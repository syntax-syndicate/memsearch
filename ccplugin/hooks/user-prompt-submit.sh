#!/usr/bin/env bash
# UserPromptSubmit hook: semantic search on every user prompt, inject relevant memories.
# Returns compact index with chunk_hash + anchor metadata for progressive disclosure.
# The main Claude agent can drill deeper with `memsearch expand` and `memsearch transcript`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Extract prompt text from input
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)

# Skip short prompts (greetings, single words, etc.)
if [ -z "$PROMPT" ] || [ "${#PROMPT}" -lt 10 ]; then
  echo '{}'
  exit 0
fi

# Need memsearch for semantic search
if [ -z "$MEMSEARCH_CMD" ]; then
  echo '{}'
  exit 0
fi

# Run semantic search
search_results=$($MEMSEARCH_CMD search "$PROMPT" --top-k 3 --json-output 2>/dev/null || true)

# Check if we got meaningful results
if [ -z "$search_results" ] || [ "$search_results" = "[]" ] || [ "$search_results" = "null" ]; then
  echo '{}'
  exit 0
fi

# Format results as compact index with chunk_hash for expand/transcript drill-down
formatted=$(echo "$search_results" | jq -r '
  to_entries | .[]? |
  "- [\(.value.source // "unknown"):\(.value.heading // "")] " +
  " \(.value.content // "" | .[0:200])\n" +
  "  `chunk_hash: \(.value.chunk_hash // "")`"
' 2>/dev/null || true)

if [ -z "$formatted" ]; then
  echo '{}'
  exit 0
fi

context="## Relevant Memories\n$formatted"
json_context=$(printf '%s' "$context" | jq -Rs .)
echo "{\"hookSpecificOutput\": {\"hookEventName\": \"UserPromptSubmit\", \"additionalContext\": $json_context}}"
