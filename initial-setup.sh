#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION="nyc3"
DEFAULT_SPACES_REGION="nyc3"
DEFAULT_KEYCLOAK_REALM="master"
DEFAULT_BACKUP_RETENTION="7d"

# Get cluster name from domain (fallback)
get_cluster_name_from_domain() {
    local domain="$1"
    echo "${domain%%.*}" | tr '.' '-' | tr '[:upper:]' '[:lower:]'
}

# Function to prompt for input with validation
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local value=""
    
    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " value
        value="${value:-$default}"
    else
        while [[ -z "$value" ]]; do
            read -p "$prompt: " value
            if [[ -z "$value" ]]; then
                echo -e "${RED}This field is required${NC}"
            fi
        done
    fi
    
    eval "$var_name='$value'"
}

# Function to validate email
validate_email() {
    local email="$1"
    local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    [[ "$email" =~ $regex ]]
}

# Function to validate domain
validate_domain() {
    local domain="$1"
    local regex="^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$"
    [[ "$domain" =~ $regex ]]
}

# Function to replace placeholders in files
replace_placeholders() {
    echo -e "${BLUE}Replacing template placeholders...${NC}"
    
    # Rename cluster directory first
    if [[ -d "flux/clusters/my-cluster" ]]; then
        echo "  Renaming cluster directory: cumulus -> $SETUP_REPO_CLUSTER_NAME"
        mv "flux/clusters/my-cluster" "flux/clusters/$SETUP_REPO_CLUSTER_NAME"
    fi
    
    # Find all relevant files and replace placeholders
    find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.tf" -o -name "*.md" -o -name "*.sh" \) \
        -not -path "./.git/*" \
        -exec grep -l -E "({{SETUP_REPO_|clusters/my-cluster)" {} \; | while read -r file; do
        echo "  Processing: $file"
        
        # Use temporary file for atomic replacement
        temp_file="${file}.tmp"
        sed \
            -e "s|{{SETUP_REPO_DOMAIN}}|$SETUP_REPO_DOMAIN|g" \
            -e "s|{{SETUP_REPO_EMAIL}}|$SETUP_REPO_EMAIL|g" \
            -e "s|{{SETUP_REPO_ADMIN_NAME}}|$SETUP_REPO_ADMIN_NAME|g" \
            -e "s|{{SETUP_REPO_CLUSTER_NAME}}|$SETUP_REPO_CLUSTER_NAME|g" \
            -e "s|{{SETUP_REPO_PROJECT_NAME}}|$SETUP_REPO_PROJECT_NAME|g" \
            -e "s|{{SETUP_REPO_REGION}}|$SETUP_REPO_REGION|g" \
            -e "s|{{SETUP_REPO_KEYCLOAK_REALM}}|$SETUP_REPO_KEYCLOAK_REALM|g" \
            -e "s|{{SETUP_REPO_BACKUP_RETENTION}}|$SETUP_REPO_BACKUP_RETENTION|g" \
            -e "s|{{SETUP_REPO_SPACES_REGION}}|$SETUP_REPO_SPACES_REGION|g" \
            -e "s|{{SETUP_REPO_LETSENCRYPT_EMAIL}}|$SETUP_REPO_LETSENCRYPT_EMAIL|g" \
            -e "s|clusters/my-cluster|clusters/$SETUP_REPO_CLUSTER_NAME|g" \
            "$file" > "$temp_file"
        
        mv "$temp_file" "$file"
    done
    
    echo -e "${GREEN}✓ Placeholders replaced successfully${NC}"
}

# Function to setup GitHub project with Kanban workflow
setup_github_project() {
    echo -e "${BLUE}Setting up GitHub project with Kanban workflow...${NC}"
    
    # Check if gh CLI is available
    if ! command -v gh >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ GitHub CLI not found - skipping project setup${NC}"
        echo -e "${YELLOW}  To setup the project manually, see WORKFLOW.md${NC}"
        return
    fi
    
    # Check if authenticated
    if ! gh auth status >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Not authenticated with GitHub CLI - skipping project setup${NC}"
        echo -e "${YELLOW}  Run 'gh auth login' then re-run setup to create project${NC}"
        return
    fi
    
    echo "  Creating GitHub labels..."
    
    # Create status labels
    gh label create "status:new-issue" --color "#a2eeef" --description "A new, untriaged issue." 2>/dev/null || true
    gh label create "status:icebox" --color "#d876e3" --description "Valid issue, but not a current priority." 2>/dev/null || true
    gh label create "status:backlog" --color "#bfd4f2" --description "Prioritized and ready for consideration." 2>/dev/null || true
    gh label create "status:to-do" --color "#fef2c0" --description "Ready for active development." 2>/dev/null || true
    gh label create "status:in-progress" --color "#2a9d8f" --description "Actively being worked on." 2>/dev/null || true
    gh label create "status:code-review" --color "#f4a261" --description "Pull request is open and awaiting review." 2>/dev/null || true
    gh label create "status:testing" --color "#e9c46a" --description "In QA, undergoing automated/manual tests." 2>/dev/null || true
    gh label create "status:ready-for-deployment" --color "#6a48d9" --description "Passed all checks and is ready to be released." 2>/dev/null || true
    gh label create "status:deployed" --color "#4CAF50" --description "Work is live in production." 2>/dev/null || true
    
    # Create type labels
    gh label create "type:bug" --color "#d73a4a" --description "An error or unintended behavior." 2>/dev/null || true
    gh label create "type:feature" --color "#0075ca" --description "A request for new functionality." 2>/dev/null || true
    gh label create "type:enhancement" --color "#a2eeef" --description "An improvement to an existing feature." 2>/dev/null || true
    gh label create "type:tech-debt" --color "#7057ff" --description "Necessary refactoring or infrastructure work." 2>/dev/null || true
    gh label create "type:epic" --color "#d876e3" --description "A large body of work." 2>/dev/null || true
    
    # Create template cleanup label
    gh label create "template-cleanup" --color "#c5def5" --description "Template cleanup task." 2>/dev/null || true
    
    
    echo "  Creating GitHub project..."
    
    # Get repository owner for project creation
    local repo_owner
    repo_owner=$(gh repo view --json owner -q .owner.login 2>/dev/null || echo "")
    
    if [[ -z "$repo_owner" ]]; then
        echo -e "${YELLOW}⚠ Could not determine repository owner - skipping project creation${NC}"
        return
    fi
    
    # Create the project
    local project_output
    if project_output=$(gh project create --owner "$repo_owner" --title "$SETUP_REPO_PROJECT_NAME Kanban Board" 2>&1); then
        echo -e "${GREEN}✓ Project created successfully${NC}"
        
        # Extract project number from output (format varies, so we'll try to get it from the URL)
        local project_url
        project_url=$(echo "$project_output" | grep -o 'https://github.com/[^/]*/[^/]*/projects/[0-9]*' || echo "")
        
        if [[ -n "$project_url" ]]; then
            local project_number
            project_number=$(echo "$project_url" | grep -o '[0-9]*$')
            echo "  Project URL: $project_url"
            echo "  Project Number: $project_number"
            
            # Create Status field with options
            echo "  Creating Status field..."
            gh project field-create "$project_number" --owner "$repo_owner" --name "Status" \
                --data-type "SINGLE_SELECT" \
                --single-select-options "New Issues,Icebox,Backlog,To Do,In Progress,Code Review,Testing,Ready for Deployment,Deployed" 2>/dev/null || true
            
            # Create label-to-status workflow
            echo "  Creating label-to-status workflow..."
            create_label_to_status_workflow "$project_number"
            
            echo -e "${GREEN}✓ GitHub project setup completed${NC}"
            echo -e "${BLUE}  Visit your project at: $project_url${NC}"
        else
            echo -e "${YELLOW}⚠ Project created but could not determine project number for automation setup${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Could not create GitHub project: $project_output${NC}"
    fi
}

# Function to setup infrastructure and credentials
setup_infrastructure() {
    echo -e "${BLUE}Setting up infrastructure and credentials...${NC}"
    
    # Check if dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "${YELLOW}=== DRY RUN MODE ===${NC}"
        echo "Would perform the following actions:"
        echo "  • Create DigitalOcean Spaces bucket: ${SETUP_REPO_CLUSTER_NAME}-tf-<random>"
        echo "  • Generate Spaces access keys"
        echo "  • Create AWS IAM user: ${SETUP_REPO_CLUSTER_NAME}-ses-smtp"
        echo "  • Create AWS IAM policy: ${SETUP_REPO_CLUSTER_NAME}-ses-policy"
        echo "  • Generate SMTP credentials"
        echo "  • Set GitHub repository secrets"
        echo -e "${YELLOW}No actual changes will be made.${NC}"
        return 0
    fi
    
    # Resource tracking for rollback capability
    local CREATED_RESOURCES=()
    local STATE_FILE="${HOME}/.startup-gitops-setup-state-${SETUP_REPO_CLUSTER_NAME}.json"
    
    # Load existing state if available
    if [[ -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}Found existing state file from previous run${NC}"
        echo "Resources created in previous run:"
        jq -r '.resources[] | "  • \(.type): \(.id)"' "$STATE_FILE" 2>/dev/null || true
        echo
        echo -e "${YELLOW}These resources will be reused if they still exist.${NC}"
        
        # Load resources into array for idempotency checks
        while IFS= read -r resource; do
            CREATED_RESOURCES+=("$resource")
        done < <(jq -r '.resources[] | "\(.type):\(.id)"' "$STATE_FILE" 2>/dev/null || true)
    fi
    
    # Cleanup function for failed setup
    cleanup_on_failure() {
        local exit_code=$?
        
        # Only cleanup if we actually failed (non-zero exit code)
        if [[ $exit_code -ne 0 ]]; then
            echo
            echo -e "${YELLOW}Setup failed. Cleaning up resources created during this run...${NC}"
            
            # Reverse the array to delete in reverse order
            local reversed_resources=()
            for ((i=${#CREATED_RESOURCES[@]}-1; i>=0; i--)); do
                reversed_resources+=("${CREATED_RESOURCES[i]}")
            done
            
            # Clean up each resource
            for resource in "${reversed_resources[@]}"; do
                IFS=':' read -r resource_type resource_id <<< "$resource"
                
                case "$resource_type" in
                    "spaces-bucket")
                        echo "  Deleting Spaces bucket: $resource_id"
                        if doctl spaces bucket delete "$resource_id" --force >/dev/null 2>&1; then
                            echo -e "    ${GREEN}✓ Deleted${NC}"
                        else
                            echo -e "    ${RED}✗ Failed to delete${NC}"
                        fi
                        ;;
                    "spaces-key")
                        echo "  Deleting Spaces access key: $resource_id"
                        if doctl spaces access-key delete "$resource_id" --force >/dev/null 2>&1; then
                            echo -e "    ${GREEN}✓ Deleted${NC}"
                        else
                            echo -e "    ${RED}✗ Failed to delete${NC}"
                        fi
                        ;;
                    "iam-user")
                        echo "  Deleting IAM user: $resource_id"
                        # First remove all access keys
                        local access_keys
                        access_keys=$(aws iam list-access-keys --user-name "$resource_id" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || true)
                        for key in $access_keys; do
                            aws iam delete-access-key --user-name "$resource_id" --access-key-id "$key" >/dev/null 2>&1 || true
                        done
                        # Detach all policies
                        local attached_policies
                        attached_policies=$(aws iam list-attached-user-policies --user-name "$resource_id" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
                        for policy in $attached_policies; do
                            aws iam detach-user-policy --user-name "$resource_id" --policy-arn "$policy" >/dev/null 2>&1 || true
                        done
                        # Delete the user
                        if aws iam delete-user --user-name "$resource_id" >/dev/null 2>&1; then
                            echo -e "    ${GREEN}✓ Deleted${NC}"
                        else
                            echo -e "    ${RED}✗ Failed to delete${NC}"
                        fi
                        ;;
                    "iam-policy")
                        echo "  Deleting IAM policy: $resource_id"
                        if aws iam delete-policy --policy-arn "$resource_id" >/dev/null 2>&1; then
                            echo -e "    ${GREEN}✓ Deleted${NC}"
                        else
                            echo -e "    ${RED}✗ Failed to delete${NC}"
                        fi
                        ;;
                    *)
                        echo "  Unknown resource type: $resource_type"
                        ;;
                esac
            done
            
            # Remove state file since we cleaned up
            rm -f "$STATE_FILE"
            
            echo -e "${YELLOW}Cleanup completed. You can safely re-run the setup.${NC}"
        else
            # Success exit - remove state file
            rm -f "$STATE_FILE" 2>/dev/null || true
        fi
    }
    
    # Set trap for cleanup on error or script exit
    trap cleanup_on_failure EXIT ERR
    
    # Function to track created resources
    track_resource() {
        local resource_type="$1"
        local resource_id="$2"
        
        CREATED_RESOURCES+=("${resource_type}:${resource_id}")
        
        # Save state to file
        {
            echo "{"
            echo "  \"cluster_name\": \"$SETUP_REPO_CLUSTER_NAME\","
            echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
            echo "  \"resources\": ["
            local first=true
            for resource in "${CREATED_RESOURCES[@]}"; do
                [[ $first == true ]] && first=false || echo ","
                IFS=':' read -r type id <<< "$resource"
                printf '    {"type": "%s", "id": "%s"}' "$type" "$id"
            done
            echo
            echo "  ]"
            echo "}"
        } > "$STATE_FILE"
    }
    
    # Function to detect available package managers
    detect_package_managers() {
        HAS_BREW=$(command -v brew >/dev/null 2>&1 && echo "true" || echo "false")
        HAS_APT=$(command -v apt-get >/dev/null 2>&1 && echo "true" || echo "false")
        HAS_YUM=$(command -v yum >/dev/null 2>&1 && echo "true" || echo "false")
        HAS_DNF=$(command -v dnf >/dev/null 2>&1 && echo "true" || echo "false")
        HAS_PACMAN=$(command -v pacman >/dev/null 2>&1 && echo "true" || echo "false")
        HAS_SNAP=$(command -v snap >/dev/null 2>&1 && echo "true" || echo "false")
        HAS_NIX=$(command -v nix-env >/dev/null 2>&1 && echo "true" || echo "false")
    }

    # Function to suggest installation command for missing tools
    suggest_install_command() {
        local tool="$1"
        
        echo
        echo -e "${YELLOW}Installation instructions for $tool:${NC}"
        
        case "$tool" in
            "doctl")
                if [[ "$HAS_BREW" == "true" ]]; then
                    echo "  brew install doctl"
                fi
                if [[ "$HAS_SNAP" == "true" ]]; then
                    echo "  sudo snap install doctl"
                fi
                if [[ "$HAS_PACMAN" == "true" ]]; then
                    echo "  yay -S doctl-bin  # or another AUR helper"
                fi
                echo "  # Direct download:"
                echo "  curl -sL https://github.com/digitalocean/doctl/releases/latest/download/doctl-$(uname -s)-$(uname -m).tar.gz | tar -xzv"
                echo "  sudo mv doctl /usr/local/bin"
                ;;
                
            "aws")
                if [[ "$HAS_BREW" == "true" ]]; then
                    echo "  brew install awscli"
                fi
                if [[ "$HAS_APT" == "true" ]]; then
                    echo "  sudo apt-get update && sudo apt-get install awscli"
                fi
                if [[ "$HAS_DNF" == "true" ]]; then
                    echo "  sudo dnf install awscli"
                elif [[ "$HAS_YUM" == "true" ]]; then
                    echo "  sudo yum install awscli"
                fi
                if [[ "$HAS_PACMAN" == "true" ]]; then
                    echo "  sudo pacman -S aws-cli"
                fi
                echo "  # Using Python pip:"
                echo "  pip3 install awscli --user"
                ;;
                
            "gh")
                if [[ "$HAS_BREW" == "true" ]]; then
                    echo "  brew install gh"
                fi
                if [[ "$HAS_APT" == "true" ]]; then
                    echo "  # Add GitHub CLI repository:"
                    echo "  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
                    echo "  echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null"
                    echo "  sudo apt update && sudo apt install gh"
                fi
                if [[ "$HAS_DNF" == "true" ]]; then
                    echo "  sudo dnf install 'dnf-command(config-manager)'"
                    echo "  sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo"
                    echo "  sudo dnf install gh"
                elif [[ "$HAS_YUM" == "true" ]]; then
                    echo "  sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo"
                    echo "  sudo yum install gh"
                fi
                if [[ "$HAS_PACMAN" == "true" ]]; then
                    echo "  sudo pacman -S github-cli"
                fi
                ;;
                
            "jq")
                if [[ "$HAS_BREW" == "true" ]]; then
                    echo "  brew install jq"
                fi
                if [[ "$HAS_APT" == "true" ]]; then
                    echo "  sudo apt-get update && sudo apt-get install jq"
                fi
                if [[ "$HAS_DNF" == "true" ]]; then
                    echo "  sudo dnf install jq"
                elif [[ "$HAS_YUM" == "true" ]]; then
                    echo "  sudo yum install jq"
                fi
                if [[ "$HAS_PACMAN" == "true" ]]; then
                    echo "  sudo pacman -S jq"
                fi
                ;;
                
            "python3")
                if [[ "$HAS_BREW" == "true" ]]; then
                    echo "  brew install python@3"
                fi
                if [[ "$HAS_APT" == "true" ]]; then
                    echo "  sudo apt-get update && sudo apt-get install python3"
                fi
                if [[ "$HAS_DNF" == "true" ]]; then
                    echo "  sudo dnf install python3"
                elif [[ "$HAS_YUM" == "true" ]]; then
                    echo "  sudo yum install python3"
                fi
                if [[ "$HAS_PACMAN" == "true" ]]; then
                    echo "  sudo pacman -S python"
                fi
                ;;
        esac
        
        # Add nix-shell option if available
        if [[ "$HAS_NIX" == "true" ]]; then
            local nix_pkg=""
            case "$tool" in
                "doctl") nix_pkg="doctl" ;;
                "aws") nix_pkg="awscli2" ;;
                "gh") nix_pkg="gh" ;;
                "jq") nix_pkg="jq" ;;
                "python3") nix_pkg="python3" ;;
            esac
            if [[ -n "$nix_pkg" ]]; then
                echo "  # Using Nix:"
                echo "  nix-shell -p $nix_pkg"
            fi
        fi
        
        # Add documentation links
        echo
        echo "For more information, visit:"
        case "$tool" in
            "doctl") echo "  https://docs.digitalocean.com/reference/doctl/how-to/install/" ;;
            "aws") echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" ;;
            "gh") echo "  https://cli.github.com/manual/installation" ;;
            "jq") echo "  https://jqlang.github.io/jq/download/" ;;
            "python3") echo "  https://www.python.org/downloads/" ;;
        esac
        echo
    }
    
    # Detect available package managers once
    detect_package_managers
    
    # Validate required CLI tools
    local required_tools=("doctl" "aws" "gh" "jq" "python3")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo -e "${RED}✗ Required tool '$tool' not found${NC}"
            suggest_install_command "$tool"
            missing_tools+=("$tool")
        fi
    done
    
    # If any tools are missing, provide batch installation option and exit
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo
        echo -e "${YELLOW}=== Installation Summary ===${NC}"
        echo "Missing tools: ${missing_tools[*]}"
        echo
        
        # Provide combined installation commands for detected package managers
        
        if [[ "$HAS_BREW" == "true" ]]; then
            echo "To install all missing tools with Homebrew:"
            local brew_pkgs=()
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "doctl") brew_pkgs+=("doctl") ;;
                    "aws") brew_pkgs+=("awscli") ;;
                    "gh") brew_pkgs+=("gh") ;;
                    "jq") brew_pkgs+=("jq") ;;
                    "python3") brew_pkgs+=("python@3") ;;
                esac
            done
            echo -e "${GREEN}  brew install ${brew_pkgs[*]}${NC}"
            echo
        fi
        
        if [[ "$HAS_APT" == "true" ]]; then
            echo "To install available tools with apt:"
            local apt_pkgs=()
            local needs_gh_repo=false
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "aws") apt_pkgs+=("awscli") ;;
                    "gh") needs_gh_repo=true ;;
                    "jq") apt_pkgs+=("jq") ;;
                    "python3") apt_pkgs+=("python3") ;;
                esac
            done
            if [[ ${#apt_pkgs[@]} -gt 0 ]]; then
                echo -e "${GREEN}  sudo apt-get update && sudo apt-get install ${apt_pkgs[*]}${NC}"
            fi
            if [[ "$needs_gh_repo" == "true" ]]; then
                echo "  # Then install GitHub CLI (see instructions above)"
            fi
            echo
        fi
        
        if [[ "$HAS_DNF" == "true" ]]; then
            echo "To install available tools with dnf:"
            local dnf_pkgs=()
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "aws") dnf_pkgs+=("awscli") ;;
                    "gh") dnf_pkgs+=("gh") ;;
                    "jq") dnf_pkgs+=("jq") ;;
                    "python3") dnf_pkgs+=("python3") ;;
                esac
            done
            if [[ ${#dnf_pkgs[@]} -gt 0 ]]; then
                echo -e "${GREEN}  sudo dnf install ${dnf_pkgs[*]}${NC}"
            fi
            echo "  # Note: gh requires repository setup (see instructions above)"
            echo
        fi
        
        if [[ "$HAS_YUM" == "true" ]]; then
            echo "To install available tools with yum:"
            local yum_pkgs=()
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "aws") yum_pkgs+=("awscli") ;;
                    "gh") yum_pkgs+=("gh") ;;
                    "jq") yum_pkgs+=("jq") ;;
                    "python3") yum_pkgs+=("python3") ;;
                esac
            done
            if [[ ${#yum_pkgs[@]} -gt 0 ]]; then
                echo -e "${GREEN}  sudo yum install ${yum_pkgs[*]}${NC}"
            fi
            echo "  # Note: gh requires repository setup (see instructions above)"
            echo
        fi
        
        if [[ "$HAS_PACMAN" == "true" ]]; then
            echo "To install available tools with pacman:"
            local pacman_pkgs=()
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "aws") pacman_pkgs+=("aws-cli") ;;
                    "gh") pacman_pkgs+=("github-cli") ;;
                    "jq") pacman_pkgs+=("jq") ;;
                    "python3") pacman_pkgs+=("python") ;;
                esac
            done
            if [[ ${#pacman_pkgs[@]} -gt 0 ]]; then
                echo -e "${GREEN}  sudo pacman -S ${pacman_pkgs[*]}${NC}"
            fi
            # Check for doctl in missing tools
            if printf '%s\n' "${missing_tools[@]}" | grep -q '^doctl$'; then
                echo "  # For doctl, use AUR: yay -S doctl-bin"
            fi
            echo
        fi
        
        if [[ "$HAS_SNAP" == "true" ]]; then
            local snap_tools=()
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "doctl") snap_tools+=("doctl") ;;
                esac
            done
            if [[ ${#snap_tools[@]} -gt 0 ]]; then
                echo "To install available tools with snap:"
                echo -e "${GREEN}  sudo snap install ${snap_tools[*]}${NC}"
                echo
            fi
        fi
        
        echo "After installing the required tools, please run this script again."
        return 1
    fi
    
    # Validate required environment variables
    local required_vars=("DIGITALOCEAN_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "ANTHROPIC_API_KEY")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo -e "${RED}✗ Required environment variable $var not set${NC}"
            echo "Please set all required variables and try again"
            return 1
        fi
    done
    
    echo -e "${GREEN}✓ All required tools and credentials available${NC}"
    
    # Check GitHub CLI authentication
    echo "  Checking GitHub CLI authentication..."
    if ! gh auth status >/dev/null 2>&1; then
        echo -e "${RED}✗ GitHub CLI not authenticated${NC}"
        echo "Please authenticate with GitHub:"
        echo "  gh auth login"
        echo "Then re-run this setup script"
        return 1
    fi
    echo -e "${GREEN}✓ GitHub CLI authenticated${NC}"
    
    # Set up DigitalOcean authentication
    echo "  Configuring DigitalOcean CLI..."
    doctl auth init --access-token "$DIGITALOCEAN_TOKEN" >/dev/null 2>&1
    
    # Set up AWS CLI
    echo "  Configuring AWS CLI..."
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" >/dev/null
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" >/dev/null
    aws configure set default.region "$AWS_SES_REGION" >/dev/null
    
    # Create DigitalOcean Spaces bucket for Terraform state
    echo "  Creating DigitalOcean Spaces bucket..."
    
    # Generate unique bucket name with random suffix
    # Format: <cluster-name>-tf-<random-6-chars>
    # Example: my-cluster-tf-a1b2c3
    # This ensures globally unique bucket names and avoids conflicts
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    local bucket_name="${SETUP_REPO_CLUSTER_NAME}-tf-${random_suffix}"
    local spaces_region="${SETUP_REPO_SPACES_REGION:-nyc3}"
    
    # Check if bucket exists before creating
    local bucket_exists=false
    local max_attempts=5
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        # Check if bucket exists
        if doctl spaces bucket list | grep -q "^$bucket_name\s"; then
            echo -e "${YELLOW}⚠ Bucket '$bucket_name' already exists, generating new name...${NC}"
            random_suffix=$(openssl rand -hex 3)
            bucket_name="${SETUP_REPO_CLUSTER_NAME}-tf-${random_suffix}"
            ((attempt++))
        else
            # Bucket doesn't exist, try to create it
            if doctl spaces bucket create "$bucket_name" --region "$spaces_region"; then
                echo -e "${GREEN}✓ Spaces bucket '$bucket_name' created${NC}"
                track_resource "spaces-bucket" "$bucket_name"
                bucket_exists=true
                break
            else
                echo -e "${RED}✗ Failed to create bucket '$bucket_name'${NC}"
                return 1
            fi
        fi
    done
    
    if [[ $bucket_exists == false ]]; then
        echo -e "${RED}✗ Failed to create unique bucket after $max_attempts attempts${NC}"
        return 1
    fi
    
    # Store the bucket name for later use
    export SPACES_BUCKET_NAME="$bucket_name"
    
    # Generate Spaces access keys using DigitalOcean API
    echo "  Creating Spaces access keys..."
    local spaces_key_response
    spaces_key_response=$(curl -s -X POST "https://api.digitalocean.com/v2/spaces/keys" \
        -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$bucket_name-key\"}")
    
    if [[ $? -eq 0 ]] && echo "$spaces_key_response" | jq -e '.key' >/dev/null 2>&1; then
        local spaces_access_key spaces_secret_key spaces_key_id
        spaces_access_key=$(echo "$spaces_key_response" | jq -r '.key.access_key_id')
        spaces_secret_key=$(echo "$spaces_key_response" | jq -r '.key.secret_access_key')
        spaces_key_id=$(echo "$spaces_key_response" | jq -r '.key.id // .key.access_key_id')
        track_resource "spaces-key" "$spaces_key_id"
        echo -e "${GREEN}✓ Spaces access keys generated${NC}"
    else
        echo -e "${RED}✗ Failed to create Spaces access keys${NC}"
        echo "Response: $spaces_key_response"
        return 1
    fi
    
    # Set up AWS SES for email
    echo "  Setting up AWS SES for domain verification..."
    
    # Verify domain with SES
    if aws ses verify-domain-identity --domain "$SETUP_REPO_DOMAIN" --region "$AWS_SES_REGION" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Domain verification initiated${NC}"
    else
        echo -e "${YELLOW}⚠ Domain verification may already be set up${NC}"
    fi
    
    # Create IAM user for SMTP
    local smtp_user="${SETUP_REPO_CLUSTER_NAME}-ses-smtp"
    echo "  Creating AWS IAM user for SMTP..."
    
    if aws iam create-user --user-name "$smtp_user" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ IAM user '$smtp_user' created${NC}"
        track_resource "iam-user" "$smtp_user"
    else
        echo -e "${YELLOW}⚠ IAM user may already exist${NC}"
    fi
    
    # Create and attach SES policy
    local policy_name="${SETUP_REPO_CLUSTER_NAME}-ses-policy"
    local policy_doc='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ses:SendEmail",
                    "ses:SendRawEmail"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    
    if aws iam create-policy --policy-name "$policy_name" --policy-document "$policy_doc" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ SES policy created${NC}"
        track_resource "iam-policy" "arn:aws:iam::$account_id:policy/$policy_name"
    else
        echo -e "${YELLOW}⚠ SES policy may already exist${NC}"
    fi
    
    # Attach policy to user
    aws iam attach-user-policy --user-name "$smtp_user" --policy-arn "arn:aws:iam::$account_id:policy/$policy_name" >/dev/null 2>&1
    
    # Create access key for SMTP user
    echo "  Generating SMTP credentials..."
    local smtp_keys_response smtp_access_key smtp_secret_key smtp_password
    smtp_keys_response=$(aws iam create-access-key --user-name "$smtp_user" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        smtp_access_key=$(echo "$smtp_keys_response" | jq -r '.AccessKey.AccessKeyId')
        smtp_secret_key=$(echo "$smtp_keys_response" | jq -r '.AccessKey.SecretAccessKey')
        
        # Generate SES SMTP password
        smtp_password=$(python3 -c "
import hashlib
import hmac
import base64

def derive_smtp_password(secret_access_key, region='us-east-1'):
    message = 'SendRawEmail'
    version = 4
    signature = hmac.new(
        key=(version.to_bytes(1, byteorder='big') + secret_access_key.encode('utf-8')),
        msg=message.encode('utf-8'),
        digestmod=hashlib.sha256
    ).digest()
    return base64.b64encode(signature).decode('utf-8')

print(derive_smtp_password('$smtp_secret_key', '$AWS_SES_REGION'))
")
        echo -e "${GREEN}✓ SMTP credentials generated${NC}"
    else
        echo -e "${RED}✗ Failed to create SMTP credentials${NC}"
        return 1
    fi
    
    # Set all GitHub secrets
    echo "  Setting GitHub repository secrets..."
    
    # Helper function to set secret with verification
    set_github_secret() {
        local secret_name="$1"
        local secret_value="$2"
        
        if gh secret set "$secret_name" --body "$secret_value"; then
            echo -e "    ${GREEN}✓ $secret_name secret set${NC}"
        else
            echo -e "    ${RED}✗ Failed to set $secret_name secret${NC}"
            return 1
        fi
    }
    
    # Core secrets provided by user
    set_github_secret "DIGITALOCEAN_TOKEN" "$DIGITALOCEAN_TOKEN" || return 1
    set_github_secret "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID" || return 1
    set_github_secret "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY" || return 1
    set_github_secret "ANTHROPIC_API_KEY" "$ANTHROPIC_API_KEY" || return 1
    
    # Generated infrastructure secrets
    set_github_secret "DIGITALOCEAN_SPACES_ACCESS_KEY" "$spaces_access_key" || return 1
    set_github_secret "DIGITALOCEAN_SPACES_SECRET_KEY" "$spaces_secret_key" || return 1
    set_github_secret "SPACES_BUCKET_NAME" "$SPACES_BUCKET_NAME" || return 1
    set_github_secret "AWS_SES_SMTP_USERNAME" "$smtp_access_key" || return 1
    set_github_secret "AWS_SES_SMTP_PASSWORD" "$smtp_password" || return 1
    
    echo -e "${GREEN}✓ All infrastructure secrets successfully configured${NC}"
    
    # Display DNS records that need to be configured
    echo
    echo -e "${YELLOW}=== DNS Configuration Required ===${NC}"
    echo "You need to add these DNS records to your domain:"
    echo
    
    # Get domain verification token
    local verification_token
    verification_token=$(aws ses get-identity-verification-attributes \
        --identities "$SETUP_REPO_DOMAIN" \
        --region "$AWS_SES_REGION" \
        --query "VerificationAttributes.\"$SETUP_REPO_DOMAIN\".VerificationToken" \
        --output text 2>/dev/null)
    
    if [[ "$verification_token" != "None" && -n "$verification_token" ]]; then
        echo "1. SES Domain Verification (TXT record):"
        echo "   Name: _amazonses.$SETUP_REPO_DOMAIN"
        echo "   Value: $verification_token"
        echo
    fi
    
    # Get DKIM tokens
    aws ses put-identity-dkim-attributes --identity "$SETUP_REPO_DOMAIN" --dkim-enabled --region "$AWS_SES_REGION" >/dev/null 2>&1
    local dkim_tokens
    dkim_tokens=$(aws ses get-identity-dkim-attributes \
        --identities "$SETUP_REPO_DOMAIN" \
        --region "$AWS_SES_REGION" \
        --query "DkimAttributes.\"$SETUP_REPO_DOMAIN\".DkimTokens" \
        --output text 2>/dev/null)
    
    if [[ "$dkim_tokens" != "None" && -n "$dkim_tokens" ]]; then
        echo "2. DKIM Records (CNAME records):"
        local i=1
        for token in $dkim_tokens; do
            echo "   Name: ${token}._domainkey.$SETUP_REPO_DOMAIN"
            echo "   Value: ${token}.dkim.amazonses.com"
            echo
            ((i++))
        done
    fi
    
    echo -e "${BLUE}After adding these DNS records, domain verification will complete automatically.${NC}"
    echo
    
    # Clear trap and state file on successful completion
    trap - EXIT ERR
    rm -f "$STATE_FILE"
}

# Function to cleanup resources from previous run
cleanup_previous_run() {
    echo -e "${BLUE}Cleaning up resources from previous run...${NC}"
    
    local cluster_name="${1:-}"
    if [[ -z "$cluster_name" ]]; then
        echo -e "${RED}✗ Cluster name required for cleanup${NC}"
        echo "Usage: $0 --cleanup <cluster-name>"
        return 1
    fi
    
    # Validate required tools for cleanup
    local required_tools=("doctl" "aws" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo -e "${RED}✗ Required tool '$tool' not found${NC}"
            echo "Please install $tool before running cleanup"
            return 1
        fi
    done
    
    # Check for required credentials
    if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]] || [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        echo -e "${RED}✗ Required credentials not set${NC}"
        echo "Please set the following environment variables:"
        echo "  • DIGITALOCEAN_TOKEN"
        echo "  • AWS_ACCESS_KEY_ID"
        echo "  • AWS_SECRET_ACCESS_KEY"
        return 1
    fi
    
    local state_file="${HOME}/.startup-gitops-setup-state-${cluster_name}.json"
    
    if [[ ! -f "$state_file" ]]; then
        echo -e "${YELLOW}⚠ No state file found for cluster '$cluster_name'${NC}"
        echo "State file path: $state_file"
        return 1
    fi
    
    echo "Found state file from $(jq -r '.timestamp' "$state_file" 2>/dev/null || echo 'unknown time')"
    
    # Parse resources from state file
    local resources
    resources=$(jq -r '.resources[] | "\(.type):\(.id)"' "$state_file" 2>/dev/null || echo "")
    
    if [[ -z "$resources" ]]; then
        echo -e "${YELLOW}⚠ No resources found in state file${NC}"
        rm -f "$state_file"
        return 0
    fi
    
    # Reverse order for cleanup
    local reversed_resources=()
    while IFS= read -r resource; do
        reversed_resources=("$resource" "${reversed_resources[@]}")
    done <<< "$resources"
    
    # Clean up each resource
    for resource in "${reversed_resources[@]}"; do
        IFS=':' read -r resource_type resource_id <<< "$resource"
        
        case "$resource_type" in
            "spaces-bucket")
                echo "  Deleting Spaces bucket: $resource_id"
                if doctl spaces bucket delete "$resource_id" --force >/dev/null 2>&1; then
                    echo -e "    ${GREEN}✓ Deleted${NC}"
                else
                    echo -e "    ${YELLOW}⚠ May already be deleted${NC}"
                fi
                ;;
            "spaces-key")
                echo "  Deleting Spaces access key: $resource_id"
                if doctl spaces access-key delete "$resource_id" --force >/dev/null 2>&1; then
                    echo -e "    ${GREEN}✓ Deleted${NC}"
                else
                    echo -e "    ${YELLOW}⚠ May already be deleted${NC}"
                fi
                ;;
            "iam-user")
                echo "  Deleting IAM user: $resource_id"
                # First remove all access keys
                local access_keys
                access_keys=$(aws iam list-access-keys --user-name "$resource_id" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || true)
                for key in $access_keys; do
                    aws iam delete-access-key --user-name "$resource_id" --access-key-id "$key" >/dev/null 2>&1 || true
                done
                # Detach all policies
                local attached_policies
                attached_policies=$(aws iam list-attached-user-policies --user-name "$resource_id" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
                for policy in $attached_policies; do
                    aws iam detach-user-policy --user-name "$resource_id" --policy-arn "$policy" >/dev/null 2>&1 || true
                done
                # Delete the user
                if aws iam delete-user --user-name "$resource_id" >/dev/null 2>&1; then
                    echo -e "    ${GREEN}✓ Deleted${NC}"
                else
                    echo -e "    ${YELLOW}⚠ May already be deleted${NC}"
                fi
                ;;
            "iam-policy")
                echo "  Deleting IAM policy: $resource_id"
                if aws iam delete-policy --policy-arn "$resource_id" >/dev/null 2>&1; then
                    echo -e "    ${GREEN}✓ Deleted${NC}"
                else
                    echo -e "    ${YELLOW}⚠ May already be deleted${NC}"
                fi
                ;;
            *)
                echo "  Unknown resource type: $resource_type"
                ;;
        esac
    done
    
    # Remove state file
    rm -f "$state_file"
    echo -e "${GREEN}✓ Cleanup completed${NC}"
    
    # Show recovery suggestions
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "  • You can now run the setup script again: $0"
    echo "  • All resources have been cleaned up"
    echo "  • No manual cleanup should be necessary"
}

# Function to setup repository secrets
setup_repository_secrets() {
    echo -e "${BLUE}Setting up repository secrets...${NC}"
    
    # Check if gh CLI is available
    if ! command -v gh >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ GitHub CLI not found - skipping repository secrets setup${NC}"
        return
    fi
    
    # Check if authenticated
    if ! gh auth status >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Not authenticated with GitHub CLI - skipping repository secrets setup${NC}"
        return
    fi
    
    echo "  Setting ADMIN_EMAIL secret..."
    if gh secret set ADMIN_EMAIL --body "$SETUP_REPO_EMAIL" 2>/dev/null; then
        echo -e "${GREEN}✓ ADMIN_EMAIL secret set${NC}"
    else
        echo -e "${YELLOW}⚠ Could not set ADMIN_EMAIL secret${NC}"
    fi
    
    echo "  Setting DOMAIN secret..."
    if gh secret set DOMAIN --body "$SETUP_REPO_DOMAIN" 2>/dev/null; then
        echo -e "${GREEN}✓ DOMAIN secret set${NC}"
    else
        echo -e "${YELLOW}⚠ Could not set DOMAIN secret${NC}"
    fi
    
    echo -e "${GREEN}✓ Repository secrets configured${NC}"
    echo
}

# Function to setup GitHub environments
setup_github_environments() {
    echo -e "${BLUE}Setting up GitHub environments...${NC}"
    
    # Check if gh CLI is available
    if ! command -v gh >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ GitHub CLI not found - skipping environment setup${NC}"
        return
    fi
    
    # Check if authenticated
    if ! gh auth status >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Not authenticated with GitHub CLI - skipping environment setup${NC}"
        return
    fi
    
    echo "  Creating production environment..."
    if gh api --method PUT repos/:owner/:repo/environments/production >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Production environment created${NC}"
        
        # Set up protection rules
        echo "  Configuring production environment protection rules..."
        
        # Note: Full protection rules require GitHub Pro/Enterprise
        # Basic environment creation works on all plans
        echo -e "${BLUE}   Note: Manual configuration required for:${NC}"
        echo "   - Required reviewers"
        echo "   - Branch restrictions (main only)"
        echo "   - Environment secrets"
        echo "   Visit: Settings → Environments → production"
    else
        echo -e "${YELLOW}⚠ Could not create production environment${NC}"
    fi
    
    echo -e "${GREEN}✓ Environment setup completed${NC}"
    echo
}

# Function to create label-to-status GitHub workflow
create_label_to_status_workflow() {
    local project_number="$1"
    
    mkdir -p .github/workflows
    
    cat > .github/workflows/label-to-status.yml << EOF
# Automatically sync GitHub issue labels to project status field
name: Sync Label to Project Status

on:
  issues:
    types: [labeled]

jobs:
  sync:
    runs-on: ubuntu-latest
    if: startsWith(github.event.label.name, 'status:')
    steps:
      - name: Sync issue status when 'status:' label is added
        env:
          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
          ORGANIZATION: \${{ github.repository_owner }}
          PROJECT_NUMBER: $project_number
          ISSUE_NODE_ID: \${{ github.event.issue.node_id }}
          STATUS_LABEL: \${{ github.event.label.name }}
        run: |
          # Extract the status name from the label, e.g., "status:in-progress" -> "In Progress"
          STATUS_VALUE=\$(echo "\$STATUS_LABEL" | sed -e 's/status://g' -e 's/-/ /g' -e 's/\b\(.\)/\u\1/g')

          # Get the Project and Status Field IDs
          gh api graphql -f query='
            query(\$org: String!, \$number: Int!) {
              organization(login: \$org){
                projectV2(number: \$number) {
                  id
                  fields(first: 20) {
                    nodes {
                      ... on ProjectV2SingleSelectField {
                        id
                        name
                        options {
                          id
                          name
                        }
                      }
                    }
                  }
                }
              }
            }' -f org=\$ORGANIZATION -f number=\$PROJECT_NUMBER > project_data.json

          PROJECT_ID=\$(jq -r '.data.organization.projectV2.id' project_data.json)
          STATUS_FIELD_ID=\$(jq -r '.data.organization.projectV2.fields.nodes[] | select(.name=="Status") | .id' project_data.json)
          STATUS_OPTION_ID=\$(jq -r --arg v "\$STATUS_VALUE" '.data.organization.projectV2.fields.nodes[] | select(.name=="Status") | .options[] | select(.name==\$v) | .id' project_data.json)

          # Get the Project Item ID
          ITEM_ID=\$(gh api graphql -f query='
            query(\$node_id: ID!){
              node(id: \$node_id) {
                ... on Issue {
                  projectItems(first: 10) {
                    nodes{
                      id
                    }
                  }
                }
              }
            }' -f node_id=\$ISSUE_NODE_ID | jq -r '.data.node.projectItems.nodes[0].id')

          # Update the item's status field if we have all the required IDs
          if [[ "\$PROJECT_ID" != "null" && "\$STATUS_FIELD_ID" != "null" && "\$STATUS_OPTION_ID" != "null" && "\$ITEM_ID" != "null" ]]; then
            gh project item-edit \\
              --id "\$ITEM_ID" \\
              --project-id "\$PROJECT_ID" \\
              --field-id "\$STATUS_FIELD_ID" \\
              --single-select-option-id "\$STATUS_OPTION_ID"
            echo "✓ Updated project item status to: \$STATUS_VALUE"
          else
            echo "⚠ Could not update project item - missing required IDs"
            echo "  PROJECT_ID: \$PROJECT_ID"
            echo "  STATUS_FIELD_ID: \$STATUS_FIELD_ID" 
            echo "  STATUS_OPTION_ID: \$STATUS_OPTION_ID"
            echo "  ITEM_ID: \$ITEM_ID"
          fi
EOF

    echo -e "${GREEN}✓ Label-to-status workflow created${NC}"
}

# Function to create cleanup issue
create_cleanup_issue() {
    echo -e "${BLUE}Creating template cleanup issue...${NC}"
    
    # Build issue body using heredoc
    local issue_body
    issue_body=$(cat <<'EOF'
## Template Cleanup Required

This issue was automatically created after repository setup to track cleanup of template artifacts.

### Cleanup Tasks
- [ ] Review generated configuration files
- [ ] Test deployment pipeline
- [ ] Remove template-specific files when ready
- [ ] Verify all placeholders were replaced correctly
EOF
)

    # Add project setup info if enabled
    if [[ "${SETUP_REPO_CREATE_PROJECT:-}" == "true" ]]; then
        issue_body+=$(cat <<'EOF'

- [ ] Review GitHub project board configuration
- [ ] Test label-to-status workflow automation
EOF
)
    fi

    issue_body+=$(cat <<'EOF'


### Eject Template Artifacts

When you're ready to remove all template artifacts and convert this to a standalone repository, run:

```bash
./initial-setup.sh --eject
```

This will:
- Remove the GitHub template workflow
- Delete template marker files  
- Remove example configuration files
- Clean up .gitignore entries
- Remove this setup script
EOF
)

    # Add project setup cleanup info if enabled
    if [[ "${SETUP_REPO_CREATE_PROJECT:-}" == "true" ]]; then
        issue_body+=$(cat <<'EOF'

- Keep GitHub project and workflow automation (manually delete if not needed)
EOF
)
    fi

    issue_body+=$(cat <<'EOF'


### Project Workflow

This repository uses a Kanban workflow with the following status labels:
- `status:new-issue` - New, untriaged issues
- `status:icebox` - Valid but not priority
- `status:backlog` - Prioritized and ready
- `status:to-do` - Ready for development
- `status:in-progress` - Being worked on
- `status:code-review` - Pull request open
- `status:testing` - In QA/testing
- `status:ready-for-deployment` - Ready to deploy
- `status:deployed` - Live in production

See [WORKFLOW.md](./WORKFLOW.md) for detailed workflow documentation.

/cc @claude
EOF
)

    # Try to create GitHub issue if gh CLI is available
    if command -v gh >/dev/null 2>&1; then
        if gh issue create \
            --title "chore: complete template cleanup and ejection" \
            --body "$issue_body" \
            --label "template-cleanup" 2>/dev/null; then
            echo -e "${GREEN}✓ GitHub issue created successfully${NC}"
        else
            echo -e "${YELLOW}⚠ Could not create GitHub issue (may need to authenticate with 'gh auth login')${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ GitHub CLI not found - skipping issue creation${NC}"
    fi
}

# Function to eject template artifacts
eject_template() {
    echo -e "${BLUE}Ejecting template artifacts...${NC}"
    
    # Remove template workflow
    echo "  Removing template workflow..."
    rm -f .github/workflows/create-setup-issue.yml
    
    # Remove label-to-status workflow (optional, user may want to keep)
    if [[ -f .github/workflows/label-to-status.yml ]]; then
        echo "  Found label-to-status workflow - keeping it (delete manually if not needed)"
    fi
    
    # Remove template marker files
    echo "  Removing template marker files..."
    rm -f .github/template.yml
    rm -f TEMPLATE_SETUP.md
    
    # Remove example files
    echo "  Removing example files..."
    rm -f config.yaml.example
    
    # Update .gitignore to remove template-specific entries
    echo "  Updating .gitignore..."
    if [[ -f .gitignore ]]; then
        # Remove template-specific gitignore entries
        sed -i '/# Template setup artifacts/,/^$/d' .gitignore 2>/dev/null || true
    fi
    
    # Remove this setup script last
    echo "  Removing setup script..."
    rm -f initial-setup.sh
    
    echo -e "${GREEN}✓ Template artifacts removed successfully${NC}"
    echo -e "${GREEN}This is now a standalone GitOps repository!${NC}"
}

# Function for interactive setup
interactive_setup() {
    echo -e "${BLUE}=== GitOps Template Setup ===${NC}"
    echo
    echo "This script will configure your repository from the template."
    echo "Press Ctrl+C at any time to cancel."
    echo
    
    # Collect configuration
    prompt_with_default "Primary domain (e.g., example.com)" "" "SETUP_REPO_DOMAIN"
    while ! validate_domain "$SETUP_REPO_DOMAIN"; do
        echo -e "${RED}Invalid domain format${NC}"
        prompt_with_default "Primary domain (e.g., example.com)" "" "SETUP_REPO_DOMAIN"
    done
    
    prompt_with_default "Admin email address" "" "SETUP_REPO_EMAIL"
    while ! validate_email "$SETUP_REPO_EMAIL"; do
        echo -e "${RED}Invalid email format${NC}"
        prompt_with_default "Admin email address" "" "SETUP_REPO_EMAIL"
    done
    
    prompt_with_default "Administrator full name" "" "SETUP_REPO_ADMIN_NAME"
    prompt_with_default "Cluster name" "$(get_cluster_name_from_domain "$SETUP_REPO_DOMAIN")" "SETUP_REPO_CLUSTER_NAME"
    prompt_with_default "Project name" "$SETUP_REPO_CLUSTER_NAME" "SETUP_REPO_PROJECT_NAME"
    prompt_with_default "DigitalOcean region" "$DEFAULT_REGION" "SETUP_REPO_REGION"
    prompt_with_default "Keycloak realm name" "$DEFAULT_KEYCLOAK_REALM" "SETUP_REPO_KEYCLOAK_REALM"
    prompt_with_default "Backup retention period" "$DEFAULT_BACKUP_RETENTION" "SETUP_REPO_BACKUP_RETENTION"
    prompt_with_default "Spaces region" "$DEFAULT_SPACES_REGION" "SETUP_REPO_SPACES_REGION"
    prompt_with_default "AWS SES region" "$SETUP_REPO_REGION" "AWS_SES_REGION"
    prompt_with_default "Let'\''s Encrypt email" "$SETUP_REPO_EMAIL" "SETUP_REPO_LETSENCRYPT_EMAIL"
    
    echo
    echo -e "${YELLOW}=== Infrastructure API Credentials ===${NC}"
    echo "The following credentials are required for automated infrastructure setup:"
    echo
    
    prompt_with_default "DigitalOcean API Token" "" "DIGITALOCEAN_TOKEN"
    prompt_with_default "AWS Access Key ID" "" "AWS_ACCESS_KEY_ID"
    prompt_with_default "AWS Secret Access Key" "" "AWS_SECRET_ACCESS_KEY"
    prompt_with_default "Anthropic API Key (for Claude integration)" "" "ANTHROPIC_API_KEY"
    
    # Ask about project setup
    echo
    read -p "Setup GitHub project with Kanban workflow? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SETUP_REPO_CREATE_PROJECT="true"
    else
        SETUP_REPO_CREATE_PROJECT="false"
    fi
    
    # Setup infrastructure and credentials
    setup_infrastructure
    
    # Process the configuration
    replace_placeholders
    create_cleanup_issue
    
    # Setup GitHub project if requested
    if [[ "$SETUP_REPO_CREATE_PROJECT" == "true" ]]; then
        setup_github_project
    fi
    
    # Setup repository secrets for deployment notifications
    setup_repository_secrets
    
    # Setup GitHub environments
    setup_github_environments
}

# Function for non-interactive setup
non_interactive_setup() {
    echo -e "${BLUE}=== GitOps Template Setup ===${NC}"
    echo
    echo "Running in non-interactive mode..."
    
    # Check required variables
    required_vars=(
        "SETUP_REPO_DOMAIN"
        "SETUP_REPO_EMAIL"
        "SETUP_REPO_ADMIN_NAME"
        "SETUP_REPO_CLUSTER_NAME"
        "SETUP_REPO_PROJECT_NAME"
        "DIGITALOCEAN_TOKEN"
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "ANTHROPIC_API_KEY"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo -e "${RED}Error: $var is not set${NC}"
            exit 1
        fi
    done
    
    # Set defaults for optional variables
    SETUP_REPO_REGION="${SETUP_REPO_REGION:-$DEFAULT_REGION}"
    SETUP_REPO_KEYCLOAK_REALM="${SETUP_REPO_KEYCLOAK_REALM:-$DEFAULT_KEYCLOAK_REALM}"
    SETUP_REPO_BACKUP_RETENTION="${SETUP_REPO_BACKUP_RETENTION:-$DEFAULT_BACKUP_RETENTION}"
    SETUP_REPO_SPACES_REGION="${SETUP_REPO_SPACES_REGION:-$DEFAULT_SPACES_REGION}"
    SETUP_REPO_LETSENCRYPT_EMAIL="${SETUP_REPO_LETSENCRYPT_EMAIL:-$SETUP_REPO_EMAIL}"
    SETUP_REPO_CREATE_PROJECT="${SETUP_REPO_CREATE_PROJECT:-false}"
    
    # Validate required inputs
    if ! validate_domain "$SETUP_REPO_DOMAIN"; then
        echo -e "${RED}Error: Invalid domain format: $SETUP_REPO_DOMAIN${NC}"
        exit 1
    fi
    
    if ! validate_email "$SETUP_REPO_EMAIL"; then
        echo -e "${RED}Error: Invalid email format: $SETUP_REPO_EMAIL${NC}"
        exit 1
    fi
    
    # Setup infrastructure and credentials
    setup_infrastructure
    
    # Process the configuration
    replace_placeholders
    create_cleanup_issue
    
    # Setup GitHub project if requested
    if [[ "$SETUP_REPO_CREATE_PROJECT" == "true" ]]; then
        setup_github_project
    fi
    
    # Setup repository secrets for deployment notifications
    setup_repository_secrets
    
    # Setup GitHub environments
    setup_github_environments
}

# Main script logic
case "${1:-}" in
    --eject)
        eject_template
        ;;
    --non-interactive)
        non_interactive_setup
        ;;
    --cleanup)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}✗ Cluster name required for cleanup${NC}"
            echo "Usage: $0 --cleanup <cluster-name>"
            exit 1
        fi
        cleanup_previous_run "$2"
        ;;
    --dry-run)
        export DRY_RUN=true
        if [[ "${2:-}" == "--non-interactive" ]]; then
            non_interactive_setup
        else
            interactive_setup
        fi
        ;;
    --help|-h)
        echo "Usage: $0 [--non-interactive|--eject|--cleanup|--dry-run|--help]"
        echo
        echo "Options:"
        echo "  --non-interactive    Use environment variables (SETUP_REPO_*)"
        echo "  --eject             Remove template artifacts"
        echo "  --cleanup <cluster>  Remove resources from a previous run"
        echo "  --dry-run           Show what would be done without making changes"
        echo "  --help, -h          Show this help message"
        echo
        echo "Required environment variables for non-interactive mode:"
        echo "  SETUP_REPO_DOMAIN        Primary domain"
        echo "  SETUP_REPO_EMAIL         Admin email address"
        echo "  SETUP_REPO_ADMIN_NAME    Administrator full name"
        echo "  SETUP_REPO_CLUSTER_NAME  Cluster name"
        echo "  SETUP_REPO_PROJECT_NAME  Project name"
        echo
        echo "Optional environment variables:"
        echo "  SETUP_REPO_REGION             DigitalOcean region (default: $DEFAULT_REGION)"
        echo "  SETUP_REPO_KEYCLOAK_REALM     Keycloak realm (default: $DEFAULT_KEYCLOAK_REALM)"
        echo "  SETUP_REPO_BACKUP_RETENTION   Backup retention (default: $DEFAULT_BACKUP_RETENTION)"
        echo "  SETUP_REPO_SPACES_REGION      Spaces region (default: $DEFAULT_SPACES_REGION)"
        echo "  SETUP_REPO_LETSENCRYPT_EMAIL  Let'\''s Encrypt email (default: same as SETUP_REPO_EMAIL)"
        echo "  SETUP_REPO_CREATE_PROJECT     Setup GitHub project (default: false)"
        ;;
    *)
        interactive_setup
        ;;
esac