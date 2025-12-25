#!/bin/bash

# qc - Quick Commit CLI
# Fast, structured git commits with conventional commit format

set -e

# ============================================================================
# CONSTANTS
# ============================================================================

readonly VALID_TYPES=("feat" "fix" "docs" "refactor" "test" "chore" "perf" "style" "wip")

declare -A DEFAULT_MESSAGES=(
    ["feat"]="add new feature"
    ["fix"]="fix issue"
    ["docs"]="update documentation"
    ["refactor"]="refactor code"
    ["test"]="update tests"
    ["chore"]="maintenance"
    ["perf"]="improve performance"
    ["style"]="style changes"
)

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

show_usage() {
    cat << EOF
Usage: qc <type> [scope] [message] [files]

Commit Types:
  feat      - New feature
  fix       - Bug fix
  docs      - Documentation changes
  refactor  - Code refactoring
  test      - Add or update tests
  chore     - Maintenance tasks
  perf      - Performance improvements
  style     - Code style changes
  wip       - Work in progress

Examples:
  qc fix "handle null response"              # fix: handle null response
  qc fix                                     # fix: fix issue (default)
  qc fix api                                 # fix(api): fix issue (default with scope)
  qc fix api "handle null response"          # fix(api): handle null response
  qc feat "add user auth" .                  # commit all files including new ones
  qc fix "bug fix" src/api.py tests/test.py # commit specific files
  qc refactor .                              # refactor: refactor code (all files)
  qc wip                                     # wip: 2025-12-25 14:30

File Handling:
  No files    → git add -u (tracked changes only)
  .           → git add . (all files including new)
  file names  → git add <files> (specific files)
EOF
    exit 0
}

print_error() {
    local message=$1
    echo "Error: $message" >&2
    echo "" >&2
}

print_success() {
    local message=$1
    echo "✓ $message"
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

validate_git_repository() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not a git repository"
        echo "This command must be run inside a git repository." >&2
        echo "Initialize one with: git init" >&2
        exit 1
    fi
}

validate_commit_type() {
    local type=$1
    
    for valid_type in "${VALID_TYPES[@]}"; do
        if [[ "$type" == "$valid_type" ]]; then
            return 0
        fi
    done
    
    print_error "Invalid commit type: '$type'"
    echo "Valid types are: ${VALID_TYPES[*]}" >&2
    echo "" >&2
    echo "Run 'qc' without arguments to see usage information." >&2
    exit 1
}

validate_files_exist() {
    local files=("$@")
    local missing_files=()
    
    for file in "${files[@]}"; do
        if [[ "$file" != "." ]] && [[ ! -e "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "File(s) not found:"
        for file in "${missing_files[@]}"; do
            echo "  - $file" >&2
        done
        exit 1
    fi
}

check_git_changes() {
    if ! git diff-index --quiet HEAD -- 2>/dev/null && ! git diff --cached --quiet 2>/dev/null; then
        return 0
    fi
    
    if ! git ls-files --others --exclude-standard | grep -q .; then
        print_error "No changes to commit"
        echo "Working tree is clean. Make some changes before committing." >&2
        exit 1
    fi
}

# ============================================================================
# GIT OPERATIONS
# ============================================================================

stage_files() {
    local files=("$@")
    
    if [[ ${#files[@]} -eq 0 ]]; then
        git add -u
    elif [[ ${#files[@]} -eq 1 ]] && [[ "${files[0]}" == "." ]]; then
        git add .
    else
        validate_files_exist "${files[@]}"
        git add "${files[@]}"
    fi
}

create_commit() {
    local message=$1
    
    if ! git commit -m "$message" 2>/dev/null; then
        print_error "Commit failed"
        echo "Git commit command failed. Check git status for details." >&2
        exit 1
    fi
}

# ============================================================================
# MESSAGE BUILDING
# ============================================================================

build_commit_message() {
    local type=$1
    local scope=$2
    local message=$3
    
    if [[ -n "$scope" ]]; then
        echo "${type}(${scope}): ${message}"
    else
        echo "${type}: ${message}"
    fi
}

generate_wip_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M")
    echo "wip: $timestamp"
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

is_likely_message() {
    local arg=$1
    # Message if it has spaces or is longer than 15 chars
    [[ "$arg" =~ \  ]] || [[ ${#arg} -gt 15 ]]
}

is_file_or_dot() {
    local arg=$1
    [[ "$arg" == "." ]] || [[ -f "$arg" ]] || [[ -d "$arg" ]]
}

parse_arguments() {
    local type=$1
    shift
    
    local scope=""
    local message=""
    local files=()
    
    if [[ $# -eq 0 ]]; then
        # No arguments: use default message
        message="${DEFAULT_MESSAGES[$type]}"
        
    elif [[ $# -eq 1 ]]; then
        # One argument: scope, message, or file
        if is_file_or_dot "$1"; then
            message="${DEFAULT_MESSAGES[$type]}"
            files=("$1")
        elif is_likely_message "$1"; then
            message=$1
        else
            scope=$1
            message="${DEFAULT_MESSAGES[$type]}"
        fi
        
    elif [[ $# -eq 2 ]]; then
        # Two arguments: various combinations
        if is_likely_message "$1"; then
            # message file(s)
            message=$1
            shift
            files=("$@")
        elif is_file_or_dot "$2"; then
            # scope file(s)
            scope=$1
            message="${DEFAULT_MESSAGES[$type]}"
            shift
            files=("$@")
        else
            # scope message
            scope=$1
            message=$2
        fi
        
    else
        # Three or more arguments
        if is_likely_message "$1"; then
            # message files...
            message=$1
            shift
            files=("$@")
        elif is_likely_message "$2"; then
            # scope message files...
            scope=$1
            message=$2
            shift 2
            files=("$@")
        else
            # scope file(s)
            scope=$1
            message="${DEFAULT_MESSAGES[$type]}"
            shift
            files=("$@")
        fi
    fi
    
    echo "$scope|$message|${files[*]}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Show usage if no arguments
    if [[ $# -eq 0 ]]; then
        show_usage
    fi
    
    # Validate environment
    validate_git_repository
    
    # Parse commit type
    local commit_type=$1
    shift
    
    validate_commit_type "$commit_type"
    
    # Handle wip special case
    if [[ "$commit_type" == "wip" ]]; then
        local wip_message=$(generate_wip_message)
        local wip_files=("$@")
        
        stage_files "${wip_files[@]}"
        create_commit "$wip_message"
        print_success "Committed: $wip_message"
        exit 0
    fi
    
    # Parse remaining arguments
    local parsed=$(parse_arguments "$commit_type" "$@")
    IFS='|' read -r scope message files_str <<< "$parsed"
    
    # Convert files string back to array
    local files=()
    if [[ -n "$files_str" ]]; then
        read -ra files <<< "$files_str"
    fi
    
    # Build commit message
    local commit_message=$(build_commit_message "$commit_type" "$scope" "$message")
    
    # Execute git operations
    stage_files "${files[@]}"
    create_commit "$commit_message"
    print_success "Committed: $commit_message"
}

# Run main function
main "$@"