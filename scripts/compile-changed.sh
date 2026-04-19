#!/usr/bin/env bash
set -euo pipefail

# Resolve working directory (default: repo root)
WORK_DIR="${WORKING_DIRECTORY:-.}"

# Parse PATHS (newline-separated globs, default **/*.gs) into an array.
# Blank lines and comments (#) are ignored.
path_globs=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    path_globs+=("$line")
done <<< "${PATHS:-**/*.gs}"
[ ${#path_globs[@]} -eq 0 ] && path_globs=("**/*.gs")

# Test whether a path matches any of the configured globs.
# Uses bash extglob so ** spans directories.
shopt -s extglob globstar nullglob
matches_paths() {
    local candidate="$1"
    local glob
    for glob in "${path_globs[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$candidate" == $glob ]]; then
            return 0
        fi
    done
    return 1
}

# Collect .gs files to compile based on ONLY_CHANGED and PATHS settings.
# Writes a newline-separated list of paths (relative to repo root) to stdout.
collect_targets() {
    if [ "${ONLY_CHANGED}" = "true" ]; then
        # Files added or modified in this PR vs. the base branch
        git diff --name-only --diff-filter=AM "origin/${BASE_REF}...HEAD" -- '*.gs'
    else
        # All .gs files under WORKING_DIRECTORY, printed as repo-relative paths
        local f
        (cd "$WORK_DIR" && find . -type f -name '*.gs' -print0) \
            | while IFS= read -r -d '' f; do
                f="${f#./}"
                if [ "$WORK_DIR" = "." ]; then
                    printf '%s\n' "$f"
                else
                    printf '%s/%s\n' "${WORK_DIR%/}" "$f"
                fi
            done
    fi
}

# Emit a GitHub Actions annotation for a compile/render error.
# Usage: emit_error <file> <message>
emit_error() {
    local file="$1"
    local msg="$2"
    # Parse "file.gs:line: message" if present
    if [[ "$msg" =~ ^([^:]+):([0-9]+):[[:space:]]*(.*) ]]; then
        local err_file="${BASH_REMATCH[1]}"
        local err_line="${BASH_REMATCH[2]}"
        local err_msg="${BASH_REMATCH[3]}"
        echo "::error file=${err_file},line=${err_line}::${err_msg}"
    else
        echo "::error file=${file}::${msg}"
    fi
}

failed_files=()
compiled_files=()

while IFS= read -r gs_file; do
    # Skip blank lines
    [ -z "$gs_file" ] && continue

    # Normalise path: strip leading ./
    gs_file="${gs_file#./}"

    # Restrict to WORKING_DIRECTORY
    if [ "$WORK_DIR" != "." ]; then
        case "$gs_file" in
            "${WORK_DIR%/}/"*) ;;
            *) continue ;;
        esac
    fi

    # Apply PATHS glob filter
    matches_paths "$gs_file" || continue

    # Skip files that no longer exist (e.g., renamed in the same PR)
    if [ ! -f "$gs_file" ]; then
        continue
    fi

    ly_file="${gs_file%.gs}.ly"
    pdf_base="${gs_file%.gs}"

    echo "Compiling: ${gs_file}"

    # Compile .gs → .ly
    if ! compile_err=$(groovescript compile "$gs_file" -o "$ly_file" 2>&1); then
        emit_error "$gs_file" "$compile_err"
        failed_files+=("$gs_file")
        continue
    fi

    # Render .ly → .pdf
    if ! render_err=$(lilypond -o "$pdf_base" "$ly_file" 2>&1); then
        emit_error "$gs_file" "$render_err"
        failed_files+=("$gs_file")
        continue
    fi

    compiled_files+=("$gs_file")
    echo "OK: ${gs_file} → ${pdf_base}.pdf"

done < <(collect_targets)

# Report results
if [ ${#compiled_files[@]} -gt 0 ]; then
    echo "Successfully compiled ${#compiled_files[@]} file(s):"
    printf '  %s\n' "${compiled_files[@]}"
fi

if [ ${#failed_files[@]} -gt 0 ]; then
    echo "Failed to compile ${#failed_files[@]} file(s):"
    printf '  %s\n' "${failed_files[@]}"

    if [ "${FAIL_ON_ERROR}" = "true" ]; then
        echo "::error::${#failed_files[@]} chart(s) failed to compile. No render commit will be made."
        exit 1
    fi
fi

# Write compiled file list for commit-artifacts.sh
printf '%s\n' "${compiled_files[@]}" > /tmp/gs_compiled_files.txt
