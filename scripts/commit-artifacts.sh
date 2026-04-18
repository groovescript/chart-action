#!/usr/bin/env bash
set -euo pipefail

compiled_list="/tmp/gs_compiled_files.txt"

# Nothing to commit if compile step produced no output
if [ ! -f "$compiled_list" ] || [ ! -s "$compiled_list" ]; then
    echo "No compiled files to commit."
    exit 0
fi

# Configure bot identity
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

staged_files=()
gs_names=()

while IFS= read -r gs_file; do
    [ -z "$gs_file" ] && continue

    pdf_file="${gs_file%.gs}.pdf"
    ly_file="${gs_file%.gs}.ly"

    if [ ! -f "$pdf_file" ]; then
        echo "Warning: expected PDF not found: ${pdf_file}"
        continue
    fi

    git add "$pdf_file"
    staged_files+=("$pdf_file")

    if [ "${COMMIT_LY}" = "true" ] && [ -f "$ly_file" ]; then
        git add "$ly_file"
        staged_files+=("$ly_file")
    fi

    gs_names+=("$(basename "$gs_file")")

done < "$compiled_list"

# Also remove orphaned .ly/.pdf whose .gs was deleted in this PR
while IFS= read -r deleted; do
    [ -z "$deleted" ] && continue
    orphan_ly="${deleted%.gs}.ly"
    orphan_pdf="${deleted%.gs}.pdf"
    for f in "$orphan_ly" "$orphan_pdf"; do
        if [ -f "$f" ]; then
            git rm --force "$f"
            staged_files+=("$f (removed)")
        fi
    done
done < <(git diff --name-only --diff-filter=D "origin/${HEAD_REF:-HEAD}...HEAD" -- '*.gs' 2>/dev/null || true)

if [ ${#staged_files[@]} -eq 0 ]; then
    echo "Nothing to commit (artifacts unchanged)."
    exit 0
fi

# Check if there are actually any staged changes
if git diff --cached --quiet; then
    echo "Nothing to commit (artifacts byte-identical to existing)."
    exit 0
fi

# Build commit message: "Re-render charts: file-a.gs, file-b.gs\n\n[skip ci]"
names_csv=$(IFS=', '; echo "${gs_names[*]}")
commit_msg="${COMMIT_MESSAGE}: ${names_csv}

[skip ci]"

git commit -m "$commit_msg"
git push origin "HEAD:${HEAD_REF}"

echo "Committed and pushed render artifacts for: ${names_csv}"
