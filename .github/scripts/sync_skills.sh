#!/usr/bin/env bash
set -e

# 1. Use Git to accurately find the absolute root of the repository
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
    # Fallback just in case it's run outside a git tree during testing
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

TARGET_DIR="$REPO_ROOT/plugins/skills"
TEMP_DIR=$(mktemp -d)\ntrap 'rm -rf "$TEMP_DIR"' EXIT

echo "Repository root correctly detected at: $REPO_ROOT"

# 2. Wipe the existing folder for a clean slate
if [ -d "$TARGET_DIR" ]; then
    echo "Purging old contents of $TARGET_DIR for a fresh sync..."
    rm -rf "$TARGET_DIR"
fi

echo "Creating fresh target directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

# Function to sync a repo into the flat target directory
sync_and_merge() {
    local repo_url=$1
    local prefix=$2
    local clone_dir="$TEMP_DIR/${prefix}_repo"

    echo "Cloning $repo_url..."
    git clone --depth 1 "$repo_url" "$clone_dir"

    # Determine if the content is in a 'skills' subdirectory or the root
    local src_path="$clone_dir/skills"
    if [ ! -d "$src_path" ]; then
        src_path="$clone_dir"
    fi

    # Handle README collision before merging
    if [ -f "$src_path/README.md" ]; then
        mv "$src_path/README.md" "$src_path/README_${prefix}.md"
    fi

    echo "Syncing contents from ${prefix} into $TARGET_DIR..."
    rsync -av --exclude='.git' "$src_path/" "$TARGET_DIR/"
}

# Sync both down into the fresh root plugins/skills folder
sync_and_merge "https://github.com/flutter/skills.git" "flutter"
sync_and_merge "https://github.com/dart-lang/skills.git" "dart"

# Cleanup temp files
rm -rf "$TEMP_DIR"
echo "Flat sync and merge successfully completed at root plugins/skills!"