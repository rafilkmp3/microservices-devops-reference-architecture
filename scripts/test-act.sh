#!/bin/bash
# Script to test GitHub Actions locally using act
# Provides easy commands to run different workflows

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if act is installed
if ! command -v act &> /dev/null; then
    echo -e "${RED}❌ act is not installed${NC}"
    echo -e "${YELLOW}Install with:${NC}"
    echo -e "  macOS: ${BLUE}brew install act${NC}"
    echo -e "  Linux: ${BLUE}curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash${NC}"
    echo -e "  Windows: ${BLUE}choco install act-cli${NC}"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker is not running${NC}"
    echo -e "${YELLOW}Please start Docker and try again${NC}"
    exit 1
fi

# Create .secrets file if it doesn't exist
if [ ! -f ".secrets" ]; then
    echo -e "${YELLOW}Creating .secrets file from template...${NC}"
    cp .secrets.example .secrets
    echo -e "${YELLOW}⚠️ Please edit .secrets file with your actual secrets${NC}"
fi

echo -e "${BLUE}🎭 GitHub Actions Local Testing with act${NC}"

# Function to run specific workflow
run_workflow() {
    local workflow_name="$1"
    local event="$2"
    
    echo -e "\n${YELLOW}Running workflow: $workflow_name${NC}"
    echo -e "${YELLOW}Event: $event${NC}"
    
    if [ -f ".github/workflows/$workflow_name" ]; then
        act "$event" -W ".github/workflows/$workflow_name" --verbose
    else
        echo -e "${RED}❌ Workflow file not found: .github/workflows/$workflow_name${NC}"
        exit 1
    fi
}

# Function to list available workflows
list_workflows() {
    echo -e "\n${BLUE}📋 Available workflows:${NC}"
    if [ -d ".github/workflows" ]; then
        ls -la .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | \
        awk '{print "  - " $NF}' | sed 's|./.github/workflows/||'
    else
        echo -e "${YELLOW}No workflows found in .github/workflows/${NC}"
    fi
}

# Function to run all workflows
run_all() {
    echo -e "\n${BLUE}🚀 Running all workflows...${NC}"
    
    if [ -d ".github/workflows" ]; then
        for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
            if [ -f "$workflow" ]; then
                workflow_name=$(basename "$workflow")
                echo -e "\n${YELLOW}Running $workflow_name...${NC}"
                act push -W "$workflow" --verbose || echo -e "${RED}❌ $workflow_name failed${NC}"
            fi
        done
    else
        echo -e "${YELLOW}No workflows found${NC}"
    fi
}

# Function to dry run (check workflow syntax)
dry_run() {
    local workflow_name="$1"
    
    echo -e "\n${YELLOW}Dry run for workflow: $workflow_name${NC}"
    
    if [ -f ".github/workflows/$workflow_name" ]; then
        act push -W ".github/workflows/$workflow_name" --dry-run
    else
        echo -e "${RED}❌ Workflow file not found: .github/workflows/$workflow_name${NC}"
        exit 1
    fi
}

# Function to show help
show_help() {
    echo -e "\n${BLUE}GitHub Actions Local Testing Script${NC}"
    echo -e "\nUsage: $0 [command] [options]"
    echo -e "\nCommands:"
    echo -e "  ${GREEN}list${NC}                     List available workflows"
    echo -e "  ${GREEN}run <workflow> [event]${NC}   Run specific workflow (default event: push)"
    echo -e "  ${GREEN}all${NC}                      Run all workflows"
    echo -e "  ${GREEN}dry <workflow>${NC}           Dry run specific workflow"
    echo -e "  ${GREEN}ci${NC}                       Run CI workflow"
    echo -e "  ${GREEN}cd${NC}                       Run CD workflow"
    echo -e "  ${GREEN}test${NC}                     Run test workflow"
    echo -e "  ${GREEN}build${NC}                    Run build workflow"
    echo -e "  ${GREEN}security${NC}                 Run security workflow"
    echo -e "  ${GREEN}help${NC}                     Show this help message"
    echo -e "\nExamples:"
    echo -e "  ${YELLOW}$0 list${NC}                        # List all workflows"
    echo -e "  ${YELLOW}$0 run ci.yml${NC}                  # Run CI workflow"
    echo -e "  ${YELLOW}$0 run ci.yml pull_request${NC}     # Run CI on pull_request event"
    echo -e "  ${YELLOW}$0 dry ci.yml${NC}                  # Dry run CI workflow"
    echo -e "  ${YELLOW}$0 all${NC}                         # Run all workflows"
    echo -e "\nNotes:"
    echo -e "  - Make sure Docker is running"
    echo -e "  - Edit .secrets file with your actual secrets"
    echo -e "  - Workflows run in isolated containers"
}

# Main script logic
case "${1:-help}" in
    "list")
        list_workflows
        ;;
    "run")
        if [ -z "$2" ]; then
            echo -e "${RED}❌ Please specify workflow name${NC}"
            echo -e "${YELLOW}Usage: $0 run <workflow> [event]${NC}"
            exit 1
        fi
        run_workflow "$2" "${3:-push}"
        ;;
    "all")
        run_all
        ;;
    "dry")
        if [ -z "$2" ]; then
            echo -e "${RED}❌ Please specify workflow name${NC}"
            echo -e "${YELLOW}Usage: $0 dry <workflow>${NC}"
            exit 1
        fi
        dry_run "$2"
        ;;
    "ci")
        run_workflow "ci.yml" "push"
        ;;
    "cd")
        run_workflow "cd.yml" "push"
        ;;
    "test")
        run_workflow "test.yml" "push"
        ;;
    "build")
        run_workflow "build.yml" "push"
        ;;
    "security")
        run_workflow "security.yml" "push"
        ;;
    "help")
        show_help
        ;;
    *)
        echo -e "${RED}❌ Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac

echo -e "\n${GREEN}✅ act testing completed${NC}"