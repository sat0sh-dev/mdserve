#!/usr/bin/env bash
# mdserve - Instant MkDocs server for any directory
# https://github.com/USERNAME/mdserve

set -euo pipefail

# Default values
TARGET_DIR="."
SPECIFIED_PORT=""

# Parse options
while getopts "p:h" opt; do
  case $opt in
    p) SPECIFIED_PORT=$OPTARG ;;
    h)
      echo "mdserve - Instant MkDocs server for any directory"
      echo ""
      echo "Usage: mdserve [-p PORT] [DIRECTORY]"
      echo ""
      echo "Options:"
      echo "  -p PORT  Use specific port (default: auto-select from 3000)"
      echo "  -h       Show this help"
      echo ""
      echo "Features:"
      echo "  - Auto port selection (3000, 3001, ...)"
      echo "  - Directory structure preserved in navigation"
      echo "  - Filename as navigation title"
      echo "  - Live reload on file changes"
      echo "  - Mermaid diagram support"
      echo "  - Material theme with dark mode"
      exit 0
      ;;
    *) echo "Usage: mdserve [-p PORT] [DIRECTORY]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

# Directory argument
TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

is_port_in_use() {
  local port=$1
  if command -v ss &>/dev/null; then
    ss -tln 2>/dev/null | grep -q ":$port "
  elif command -v netstat &>/dev/null; then
    netstat -tln 2>/dev/null | grep -q ":$port "
  else
    (echo >/dev/tcp/localhost/"$port") 2>/dev/null
  fi
}

find_free_port() {
  local port=3000
  while is_port_in_use "$port"; do
    ((port++))
    if [ "$port" -gt 3100 ]; then
      echo "No available port found in range 3000-3100" >&2
      exit 1
    fi
  done
  echo "$port"
}

# Use specified port or find free one
if [ -n "$SPECIFIED_PORT" ]; then
  PORT=$SPECIFIED_PORT
else
  PORT=$(find_free_port)
fi

TEMP_DIR=$(mktemp -d)
DOCS_DIR="$TEMP_DIR/docs"
mkdir -p "$DOCS_DIR"

cleanup() {
  rm -rf "$TEMP_DIR"
  # Kill background sync process if running
  jobs -p | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT

# Sync markdown files with front matter (title = filename)
sync_docs() {
  # Clear and recreate docs dir to handle deletions
  rm -rf "$DOCS_DIR"
  mkdir -p "$DOCS_DIR"

  find "$TARGET_DIR" -name "*.md" -type f \
    ! -path '*/build/*' ! -path '*/.git/*' ! -path '*/.repo/*' \
    ! -path '*/node_modules/*' ! -path '*/__pycache__/*' \
    ! -path '*/out/*' ! -path '*/tmp/*' ! -path '*/cache/*' \
    ! -path '*/target/*' ! -path '*/.venv/*' ! -path '*/venv/*' \
    2>/dev/null | while read -r src; do
    relpath="${src#"$TARGET_DIR"/}"
    dest="$DOCS_DIR/$relpath"
    mkdir -p "$(dirname "$dest")"

    # Get filename without extension for title
    filename=$(basename "$src" .md)

    # Check if file already has front matter
    if head -1 "$src" | grep -q '^---$'; then
      # Already has front matter, copy as-is
      cp "$src" "$dest"
    else
      # Add front matter with filename as title
      {
        echo "---"
        echo "title: $filename"
        echo "---"
        echo ""
        cat "$src"
      } > "$dest"
    fi
  done
}

# Initial sync
echo "Syncing documentation files..."
sync_docs

# Generate mkdocs.yml
cat > "$TEMP_DIR/mkdocs.yml" << 'YAMLEOF'
site_name: Documentation
docs_dir: docs
theme:
  name: material
  palette:
    - scheme: default
      primary: indigo
      accent: indigo
      toggle:
        icon: material/brightness-7
        name: Switch to dark mode
    - scheme: slate
      primary: indigo
      accent: indigo
      toggle:
        icon: material/brightness-4
        name: Switch to light mode
  features:
    - navigation.instant
    - navigation.tracking
    - navigation.expand
    - toc.follow
    - search.suggest
    - search.highlight

plugins:
  - search

markdown_extensions:
  - pymdownx.superfences:
      custom_fences:
        - name: mermaid
          class: mermaid
          format: !!python/name:pymdownx.superfences.fence_code_format
  - pymdownx.highlight:
      anchor_linenums: true
  - pymdownx.inlinehilite
  - pymdownx.snippets
  - pymdownx.tabbed:
      alternate_style: true
  - toc:
      permalink: true
  - admonition
  - pymdownx.details
  - pymdownx.mark
  - attr_list
  - md_in_html
  - tables
YAMLEOF

# Background file watcher to sync changes
(
  if command -v inotifywait &>/dev/null; then
    # Use inotifywait for efficient watching
    while inotifywait -r -e modify,create,delete,move "$TARGET_DIR" \
        --exclude '(\.git|\.repo|build|node_modules|__pycache__|\.sock|target|\.venv|venv)' 2>/dev/null; do
      sync_docs
    done
  else
    # Fallback: poll every 2 seconds
    while true; do
      sleep 2
      sync_docs
    done
  fi
) &

echo "Serving documentation from: $TARGET_DIR"
echo "URL: http://localhost:$PORT"
echo ""

cd "$TEMP_DIR"
exec mkdocs serve -a "0.0.0.0:$PORT"
