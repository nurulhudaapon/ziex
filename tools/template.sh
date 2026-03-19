#!/bin/bash

# Ziex Template Management Tool
# This tool helps manage template overrides, synchronization, and health.

set -e

# Get the root directory of the repository
ROOT_DIR=$(git rev-parse --show-toplevel)
TEMPLATES_DIR="$ROOT_DIR/templates"
BASE_DIR="$TEMPLATES_DIR/_base"
ROOT_GITIGNORE="$TEMPLATES_DIR/.gitignore"

show_help() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list                        List all available templates (except _base)."
    echo "  create <name>               Create a new template skeleton."
    echo "  populate [name]             Populate template(s) with missing files from _base."
    echo "                              If name is omitted, all templates are populated."
    echo "  clean [name]                Remove populated files (git-ignored) from templates."
    echo "  diff <name> [file]          Show differences between a template override and its base version."
    echo "  help                        Show this help message."
}

list_templates() {
    echo "Available templates:"
    for dir in "$TEMPLATES_DIR"/*/; do
        template_name=$(basename "$dir")
        if [ "$template_name" != "_base" ]; then
            local unignored_count=$(git ls-files "$TEMPLATES_DIR/$template_name" | wc -l)
            echo "  - $template_name ($unignored_count files overridden)"
        fi
    done
}

create_template() {
    local name=$1
    if [ -z "$name" ]; then
        echo "Error: Template name required."
        exit 1
    fi

    local target_dir="$TEMPLATES_DIR/$name"
    if [ -d "$target_dir" ]; then
        echo "Error: Template '$name' already exists."
        exit 1
    fi

    echo "Creating new template: $name"
    mkdir -p "$target_dir"

    # Create a minimal .gitignore for the new template
    cat > "$target_dir/.gitignore" <<EOF
.zig-cache/
zig-out/
node_modules/
EOF

    # Update templates/.gitignore to start tracking the folder and its specific overrides
    # Append to the end of the file
    echo "Updating $ROOT_GITIGNORE"
    cat >> "$ROOT_GITIGNORE" <<EOF

# $name template
!$name/.gitignore
!$name/package.json
!$name/build.zig
EOF

    echo "Template skeleton created at $target_dir"
    echo "Suggested files to override: .gitignore, package.json, build.zig"
}

populate_template() {
    local template=$1
    echo "Populating template: $template..."

    if [ "$template" == "_base" ]; then
        echo "Skipping _base template."
        return
    fi

    local target_dir="$TEMPLATES_DIR/$template"
    if [ ! -d "$target_dir" ]; then
        echo "Error: Template directory '$target_dir' not found."
        exit 1
    fi

    # Find all files in _base
    cd "$ROOT_DIR"
    find "templates/_base" -type f | while read -r base_file; do
        # Calculate relative path from _base
        rel_path="${base_file#templates/_base/}"
        target_file="templates/$template/$rel_path"

        # Check if the target file should be overwritten or created
        # We overwrite if it doesn't exist OR if it's currently ignored by git
        if [ ! -f "$target_file" ] || git check-ignore -q "$target_file"; then
            mkdir -p "$(dirname "$target_file")"
            cp "$base_file" "$target_file"
        fi
    done
}

clean_template() {
    local template=$1
    echo "Cleaning template: $template..."

    if [ "$template" == "_base" ]; then
        echo "Skipping _base template."
        return
    fi

    local target_dir="$TEMPLATES_DIR/$template"
    if [ ! -d "$target_dir" ]; then
        echo "Error: Template directory '$target_dir' not found."
        exit 1
    fi

    cd "$ROOT_DIR"
    # Use git to list ignored files and remove them
    # Note: we use -X to remove only ignored files, -d to remove directories if empty
    git clean -fdX "templates/$template/"
}

diff_template() {
    local template=$1
    local file=$2

    if [ -z "$template" ]; then
        echo "Error: Template name required."
        exit 1
    fi

    if [ -n "$file" ]; then
        local target_file="templates/$template/$file"
        local base_file="templates/_base/$file"
        if [ ! -f "$target_file" ]; then echo "Error: Override file not found."; exit 1; fi
        if [ ! -f "$base_file" ]; then echo "Error: Base file not found."; exit 1; fi
        diff -u "$base_file" "$target_file" || true
    else
        # Diff all overridden/tracked files
        git ls-files "templates/$template" | while read -r target_file; do
            rel_path="${target_file#templates/$template/}"
            base_file="templates/_base/$rel_path"
            if [ -f "$base_file" ]; then
                echo "--- Diff: $rel_path ---"
                diff -u "$base_file" "$target_file" || true
                echo ""
            fi
        done
    fi
}

case "$1" in
    list)
        list_templates
        ;;
    create)
        create_template "$2"
        ;;
    populate)
        shift
        if [ -n "$1" ]; then
            populate_template "$1"
        else
            for dir in "$TEMPLATES_DIR"/*/; do
                template_name=$(basename "$dir")
                if [ "$template_name" != "_base" ]; then
                    populate_template "$template_name"
                fi
            done
        fi
        echo "Done."
        ;;
    clean)
        shift
        if [ -n "$1" ]; then
            clean_template "$1"
        else
            for dir in "$TEMPLATES_DIR"/*/; do
                template_name=$(basename "$dir")
                if [ "$template_name" != "_base" ]; then
                    clean_template "$template_name"
                fi
            done
        fi
        echo "Done."
        ;;
    diff)
        diff_template "$2" "$3"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        if [ -n "$1" ]; then
            echo "Unknown command: $1"
        fi
        show_help
        exit 1
        ;;
esac
