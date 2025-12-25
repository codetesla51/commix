#!/bin/bash

# qc - Quick Commit CLI
# Fast, structured git commits with conventional commit format

set -e

# ============================================================================
# CONSTANTS
# ============================================================================

readonly VALID_TYPES=("feat" "fix" "docs" "refactor" "test" "chore" "perf" "style" "wip")

# Colors - only use if terminal supports them
if [[ -t 1 ]] && command -v tput &> /dev/null && [[ $(tput colors) -ge 8 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly NC=''
fi

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
${BLUE}Usage:${NC} qc <type> [scope] [message] [files] [flags]

${YELLOW}Commit Types:${NC}
  feat      - New feature
  fix       - Bug fix
  docs      - Documentation changes
  refactor  - Code refactoring
  test      - Add or update tests
  chore     - Maintenance tasks
  perf      - Performance improvements
  style     - Code style changes
  wip       - Work in progress

${YELLOW}Flags:${NC}
  -p, --push    Push to remote after committing
  --amend       Amend the last commit message (supports -p flag)

${YELLOW}Examples:${NC}
  qc fix "handle null response"              # fix: handle null response
  qc fix                                     # fix: fix issue (default)
  qc fix api                                 # fix(api): fix issue (default with scope)
  qc fix api "handle null response"          # fix(api): handle null response
  qc feat "add user auth" .                  # commit all files including new ones
  qc fix "bug fix" src/api.py tests/test.py # commit specific files
  qc refactor . -p                           # commit and push
  qc fix --amend "better message"            # amend last commit with new message
  qc fix api --amend -p                      # amend and push
  qc wip -p                                  # wip with push

${YELLOW}File Handling:${NC}
  No files    → git add -u (tracked changes only)
  .           → git add . (all files including new)
  file names  → git add <files> (specific files)
EOF
    exit 0
}

print_error() {
    local message=$1
    echo -e "${RED}Error:${NC} $message" >&2
    echo "" >&2
}

print_success() {
    local message=$1
    echo -e "${GREEN}✓${NC} $message"
}

print_info() {
    local message=$1
    echo -e "${BLUE}→${NC} $message"
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
            # Check if default message exists for this type
            if [[ -z "${DEFAULT_MESSAGES[$type]}" ]]; then
                print_error "No default message configured for type '$type'"
                echo "This is a configuration error. Please report this issue." >&2
                exit 1
            fi
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
    # Check if there are any changes at all
    if git diff-index --quiet HEAD -- 2>/dev/null && \
       git diff --cached --quiet 2>/dev/null && \
       ! git ls-files --others --exclude-standard | grep -q .; then
        print_error "No changes to commit"
        echo "Working tree is clean. Make some changes before committing." >&2
        exit 1
    fi
}

validate_remote_exists() {
    if ! git remote | grep -q .; then
        print_error "No remote repository configured"
        echo "Add a remote with: git remote add origin <url>" >&2
        exit 1
    fi
    
    # Check if current branch has upstream
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} > /dev/null 2>&1; then
        print_error "Current branch '$current_branch' has no upstream branch"
        echo "Set upstream with: git push -u origin $current_branch" >&2
        exit 1
    fi
}

validate_can_amend() {
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        print_error "Cannot amend - no previous commit exists"
        echo "Make an initial commit first before using --amend" >&2
        exit 1
    fi
}

# ============================================================================
# GIT OPERATIONS
# ============================================================================

stage_files() {
    local files=("$@")
    
    if [[ ${#files[@]} -eq 0 ]]; then
        if ! git add -u 2>&1; then
            print_error "Failed to stage files"
            exit 1
        fi
    elif [[ ${#files[@]} -eq 1 ]] && [[ "${files[0]}" == "." ]]; then
        if ! git add . 2>&1; then
            print_error "Failed to stage all files"
            exit 1
        fi
    else
        validate_files_exist "${files[@]}"
        if ! git add "${files[@]}" 2>&1; then
            print_error "Failed to stage specified files"
            exit 1
        fi
    fi
}

create_commit() {
    local message=$1
    
    if ! git commit -m "$message" 2>&1; then
        print_error "Commit failed"
        echo "Run 'git status' to see what went wrong." >&2
        exit 1
    fi
}

amend_commit() {
    local message=$1
    
    if ! git commit --amend -m "$message" 2>&1; then
        print_error "Amend failed"
        echo "Run 'git status' to see what went wrong." >&2
        exit 1
    fi
}

push_to_remote() {
    print_info "Pushing to remote..."
    
    local push_output
    if ! push_output=$(git push 2>&1); then
        print_error "Push failed"
        echo "$push_output" >&2
        echo "" >&2
        echo "You may need to pull first or resolve conflicts." >&2
        exit 1
    fi
    
    print_success "Pushed to remote"
}

push_force_to_remote() {
    print_info "Force pushing to remote (amended commit)..."
    
    local push_output
    if ! push_output=$(git push --force-with-lease 2>&1); then
        print_error "Force push failed"
        echo "$push_output" >&2
        echo "" >&2
        echo "This can happen if the remote has newer commits." >&2
        echo "Use 'git pull --rebase' to sync, then try again." >&2
        exit 1
    fi
    
    print_success "Force pushed to remote"
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
    local timestamp=$(date "+%Y-%m-%d %H:%M %Z")
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

is_flag() {
    local arg=$1
    [[ "$arg" == "-p" ]] || [[ "$arg" == "--push" ]] || [[ "$arg" == "--amend" ]]
}

extract_flags() {
    local should_push=false
    local should_amend=false
    local args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--push)
                should_push=true
                shift
                ;;
            --amend)
                should_amend=true
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    echo "$should_push|$should_amend|${args[*]}"
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
    
    # Extract flags from all arguments
    local flag_result=$(extract_flags "$@")
    IFS='|' read -r should_push should_amend remaining_args <<< "$flag_result"
    
    # Convert remaining args back to array
    local args=()
    if [[ -n "$remaining_args" ]]; then
        read -ra args <<< "$remaining_args"
    fi
    
    # Handle amend special case
    if [[ "$should_amend" == "true" ]]; then
        validate_can_amend
        
        local scope=""
        local message=""
        
        # Parse arguments for new message
        if [[ ${#args[@]} -eq 0 ]]; then
            message="${DEFAULT_MESSAGES[$commit_type]}"
        elif [[ ${#args[@]} -eq 1 ]]; then
            if is_likely_message "${args[0]}"; then
                message=${args[0]}
            else
                scope=${args[0]}
                message="${DEFAULT_MESSAGES[$commit_type]}"
            fi
        else
            scope=${args[0]}
            message=${args[1]}
        fi
        
        local commit_message=$(build_commit_message "$commit_type" "$scope" "$message")
        amend_commit "$commit_message"
        print_success "Amended: $commit_message"
        
        # Push if requested (force with lease since we amended)
        if [[ "$should_push" == "true" ]]; then
            validate_remote_exists
            push_force_to_remote
        fi
        
        exit 0
    fi
    
    # Handle wip special case
    if [[ "$commit_type" == "wip" ]]; then
        local wip_message=$(generate_wip_message)
        
        stage_files "${args[@]}"
        create_commit "$wip_message"
        print_success "Committed: $wip_message"
        
        if [[ "$should_push" == "true" ]]; then
            validate_remote_exists
            push_to_remote
        fi
        
        exit 0
    fi
    
    # Parse remaining arguments for normal commits
    local parsed=$(parse_arguments "$commit_type" "${args[@]}")
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
    
    # Push if requested
    if [[ "$should_push" == "true" ]]; then
        validate_remote_exists
        push_to_remote
    fi
}

# Run main function
main "$@"