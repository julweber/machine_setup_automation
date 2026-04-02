# Shared CLI helpers live here.

# detect_feature_from_branch: echo the feature name extracted from the current
# git branch (feat/<name> pattern), or empty string if not on a feature branch.
# Uses symbolic-ref to work correctly even in repos with no commits yet.
detect_feature_from_branch() {
    local branch
    branch="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    case "$branch" in
        feat/*)
            echo "${branch#feat/}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# list_features: echo the names of all features that have a spec directory under
# specification/features/, sorted alphabetically.
list_features() {
    local features_dir="${PWD}/specification/features"
    if [ ! -d "$features_dir" ]; then
        return
    fi
    find "$features_dir" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
        basename "$dir"
    done
}

# is_kebab_case: return 0 if the name contains only lowercase letters, digits,
# and hyphens, and does not start or end with a hyphen.
is_kebab_case() {
    local name="$1"
    if [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [[ "$name" =~ ^[a-z0-9]$ ]]; then
        return 0
    fi
    return 1
}

# validate_kebab: print an error and exit 1 if name is not valid kebab-case.
validate_kebab() {
    local name="$1"
    if ! is_kebab_case "$name"; then
        echo "Error: Invalid feature name '${name}'." >&2
        echo "       Feature names must be kebab-case (lowercase letters, digits, and hyphens)." >&2
        echo "       Example: user-authentication" >&2
        exit 1
    fi
}

# validate_project: ensure specification/project/ exists with at least one .md
# file, or exit 1 with init guidance.
validate_project() {
    local spec_project_dir="${PWD}/specification/project"
    if [ ! -d "$spec_project_dir" ]; then
        echo "Error: Project not initialized. '${spec_project_dir}' does not exist." >&2
        echo "" >&2
        echo "       Initialize the project first:" >&2
        echo "         spec init <project-name>" >&2
        exit 1
    fi

    local md_count
    md_count="$(find "$spec_project_dir" -maxdepth 1 -name '*.md' | wc -l)"
    if [ "$md_count" -eq 0 ]; then
        echo "Error: Project not initialized. No spec files in '${spec_project_dir}'." >&2
        echo "" >&2
        echo "       Initialize the project first:" >&2
        echo "         spec init <project-name>" >&2
        exit 1
    fi
}

# json_string: JSON-encode an arbitrary string using python3.
json_string() {
    printf '%s' "$1" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'
}

# check_yq: verify yq is available, exit 1 with guidance if not.
check_yq() {
    if ! yq --version > /dev/null 2>&1; then
        echo "Error: yq is required but not installed." >&2
        echo "  Install it from: https://github.com/mikefarah/yq" >&2
        exit 1
    fi
}

# confirm_overwrite: prompt before overwriting an existing path. Exits 1 unless
# the user explicitly confirms with y/Y.
confirm_overwrite() {
    local label="$1"
    local path="$2"
    local answer

    if [ -z "$label" ] || [ -z "$path" ]; then
        echo "Error: confirm_overwrite requires a label and path." >&2
        exit 1
    fi

    printf "Overwrite existing %s? [y/N] " "$label" >&2
    read -r answer || answer="n"
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Cancelled." >&2
        exit 1
    fi
}
