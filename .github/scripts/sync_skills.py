#!/usr/bin/env python3
"""Synchronizes external skills repositories into plugins/skills and updates plugin.json."""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def get_repo_root() -> Path:
    """Finds the absolute root of the git repository."""
    script_dir = Path(__file__).resolve().parent
    try:
        root = subprocess.check_output(
            ["git", "-C", str(script_dir), "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return Path(root)
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback if run outside git
        return script_dir.parent.parent


def sync_repo(repo_url: str, prefix: str, target_dir: Path, temp_dir: Path) -> None:
    """Clones a git repo and copies its skills contents into target_dir."""
    clone_dir = temp_dir / f"{prefix}_repo"
    print(f"Cloning {repo_url}...")
    subprocess.run(
        ["git", "clone", "--depth", "1", repo_url, str(clone_dir)],
        check=True,
    )

    # Determine if the content is in a 'skills' subdirectory or the root
    src_path = clone_dir / "skills"
    if not src_path.is_dir():
        src_path = clone_dir

    # Handle README collision before merging
    readme = src_path / "README.md"
    if readme.is_file():
        readme.rename(src_path / f"README_{prefix}.md")

    print(f"Syncing contents from {prefix} into {target_dir}...")
    # Copy contents into target_dir (similar to rsync -av --exclude='.git')
    for item in src_path.iterdir():
        if item.name == ".git":
            continue
        dest = target_dir / item.name
        if item.is_dir():
            shutil.copytree(item, dest, dirs_exist_ok=True)
        else:
            shutil.copy2(item, dest)


def update_plugin_version(plugin_json: Path) -> None:
    """Bumps the patch version in plugin.json."""
    if not plugin_json.is_file():
        print(
            f"Warning: {plugin_json} not found, skipping version update.",
            file=sys.stderr,
        )
        return

    print(f"Updating plugin version in {plugin_json}...")
    try:
        with open(plugin_json, "r", encoding="utf-8") as f:
            data = json.load(f)

        version_parts = data.get("version", "1.0.0").split(".")
        version_parts[-1] = str(int(version_parts[-1]) + 1)
        new_version = ".".join(version_parts)
        data["version"] = new_version

        with open(plugin_json, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")

        print(f"Updated plugin version to {new_version}")
    except Exception as e:
        print(f"Error updating plugin version: {e}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    repo_root = get_repo_root()
    target_dir = repo_root / "plugins" / "skills"
    plugin_json = repo_root / "plugins" / ".claude-plugin" / "plugin.json"

    print(f"Repository root correctly detected at: {repo_root}")

    # Wipe existing folder for a clean slate
    if target_dir.is_dir():
        print(f"Purging old contents of {target_dir} for a fresh sync...")
        shutil.rmtree(target_dir)

    print(f"Creating fresh target directory: {target_dir}")
    target_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as temp_dir_str:
        temp_dir = Path(temp_dir_str)
        sync_repo(
            "https://github.com/flutter/skills.git", "flutter", target_dir, temp_dir
        )
        sync_repo(
            "https://github.com/dart-lang/skills.git", "dart", target_dir, temp_dir
        )

    update_plugin_version(plugin_json)

    print(f"Flat sync and merge successfully completed at root {target_dir}!")


if __name__ == "__main__":
    main()
