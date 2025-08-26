#!/bin/bash
# Unified Test Runner - Executes tests across all environments
# Orchestrates development, act, and Kubernetes testing with comparison

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

RESULTS_DIR="test-results"
UNIFIED_REPORT="$RESULTS_DIR/unified-test-report.json"
COMPARISON_REPORT="$RESULTS_DIR/comparison-report.md"

echo -e "${CYAN}🌍 Unified Multi-Environment Test Runner${NC}"
echo -e "${CYAN}=======================================${NC}"
echo -e "${BLUE}Testing across Development, GitHub Actions (act), and Kubernetes${NC}"

# Create results directory
mkdir -p $RESULTS_DIR

# Initialize unified test results
cat > $UNIFIED_REPORT << EOF
{
  "test_suite": "multi-environment",
  "timestamp": "$(date -Iseconds)",
  "environments": {
    "development": {"status": "pending"},
    "act": {"status": "pending"},
    "kubernetes": {"status": "pending"}
  },
  "comparison": {},
  "overall_status": "running"
}
EOF

# Function to update overall results
update_unified_results() {
    local env="$1"
    local status="$2"
    local report_file="$3"
    
    python3 -c "
import json
with open('$UNIFIED_REPORT', 'r') as f:
    data = json.load(f)
data['environments']['$env']['status'] = '$status'
data['environments']['$env']['report_file'] = '$report_file'
data['environments']['$env']['timestamp'] = '$(date -Iseconds)'
with open('$UNIFIED_REPORT', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

# Function to run environment test
run_environment_test() {
    local env_name="$1"
    local script_name="$2"
    local description="$3"
    
    echo -e "\n${BLUE}🧪 Testing Environment: $env_name${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo -e "${YELLOW}$description${NC}"
    
    start_time=$(date +%s)
    
    if chmod +x "scripts/$script_name" && "./scripts/$script_name"; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo -e "\n${GREEN}✅ $env_name testing completed successfully (${duration}s)${NC}"
        update_unified_results "$env_name" "passed" "$RESULTS_DIR/${env_name}-test-report.json"
        return 0
    else
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo -e "\n${RED}❌ $env_name testing failed (${duration}s)${NC}"
        update_unified_results "$env_name" "failed" "$RESULTS_DIR/${env_name}-test-report.json"
        return 1
    fi
}

# Phase 1: Development Environment Testing
echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}Phase 1: Development Environment Testing${NC}"
echo -e "${CYAN}========================================${NC}"

run_environment_test "development" "test-dev-full.sh" "Local development with hot reload, direct database connections"
DEV_RESULT=$?

# Phase 2: GitHub Actions Local Testing (act)
echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}Phase 2: GitHub Actions Local Testing${NC}"
echo -e "${CYAN}========================================${NC}"

run_environment_test "act" "test-act-full.sh" "CI/CD workflows with containerized services"
ACT_RESULT=$?

# Phase 3: Kubernetes Local Testing
echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}Phase 3: Kubernetes Local Testing${NC}"
echo -e "${CYAN}========================================${NC}"

run_environment_test "kubernetes" "test-k8s-full.sh" "Full orchestration with OrbStack cluster"
K8S_RESULT=$?

# Phase 4: Results Comparison and Analysis
echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}Phase 4: Results Comparison & Analysis${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "${YELLOW}Analyzing results across environments...${NC}"

# Generate comparison report
cat > $COMPARISON_REPORT << 'EOF'
# Multi-Environment Test Comparison Report

## Overview
This report compares test results across Development, GitHub Actions (act), and Kubernetes environments.

EOF

echo "Generated: $(date)" >> $COMPARISON_REPORT
echo "" >> $COMPARISON_REPORT

# Function to extract metrics from reports
extract_metrics() {
    local report_file="$1"
    local env_name="$2"
    
    if [ -f "$report_file" ]; then
        python3 -c "
import json
import sys

try:
    with open('$report_file', 'r') as f:
        data = json.load(f)
    
    # Extract common metrics
    metrics = {}
    
    # Test results
    if 'tests' in data:
        total_tests = len(data['tests'])
        passed_tests = sum(1 for t in data['tests'].values() if t.get('status') == 'passed')
        failed_tests = sum(1 for t in data['tests'].values() if t.get('status') == 'failed')
    elif 'workflows' in data:
        total_tests = len(data['workflows'])
        passed_tests = sum(1 for t in data['workflows'].values() if t.get('status') == 'passed')
        failed_tests = sum(1 for t in data['workflows'].values() if t.get('status') == 'failed')
    else:
        total_tests = passed_tests = failed_tests = 0
    
    metrics['total_tests'] = total_tests
    metrics['passed_tests'] = passed_tests
    metrics['failed_tests'] = failed_tests
    metrics['pass_rate'] = round((passed_tests / total_tests * 100) if total_tests > 0 else 0, 2)
    
    # Performance metrics
    performance = data.get('performance', {})
    if 'configuration_service_response_time' in performance:
        metrics['config_response_time'] = float(performance['configuration_service_response_time'])
    if 'log_service_response_time' in performance:
        metrics['log_response_time'] = float(performance['log_service_response_time'])
    
    # Environment specific
    metrics['environment'] = '$env_name'
    metrics['status'] = data.get('status', 'unknown')
    
    print(json.dumps(metrics))
except Exception as e:
    print(json.dumps({'error': str(e), 'environment': '$env_name'}))
" 2>/dev/null || echo '{"error": "Cannot parse report", "environment": "'$env_name'"}'
    else
        echo '{"error": "Report file not found", "environment": "'$env_name'"}'
    fi
}

# Extract metrics for each environment
DEV_METRICS=$(extract_metrics "$RESULTS_DIR/dev-test-report.json" "development")
ACT_METRICS=$(extract_metrics "$RESULTS_DIR/act-test-report.json" "act")
K8S_METRICS=$(extract_metrics "$RESULTS_DIR/k8s-test-report.json" "kubernetes")

# Generate detailed comparison
python3 -c "
import json
import sys

# Load metrics
dev_metrics = json.loads('$DEV_METRICS')
act_metrics = json.loads('$ACT_METRICS')
k8s_metrics = json.loads('$K8S_METRICS')

all_metrics = [dev_metrics, act_metrics, k8s_metrics]

# Generate comparison table
print('## Test Results Summary')
print('')
print('| Environment | Total Tests | Passed | Failed | Pass Rate |')
print('|-------------|-------------|--------|--------|-----------|')

for metrics in all_metrics:
    env = metrics.get('environment', 'unknown')
    total = metrics.get('total_tests', 0)
    passed = metrics.get('passed_tests', 0)
    failed = metrics.get('failed_tests', 0)
    pass_rate = metrics.get('pass_rate', 0)
    print(f'| {env.title()} | {total} | {passed} | {failed} | {pass_rate}% |')

print('')
print('## Performance Comparison')
print('')
print('| Environment | Config Service (s) | Log Service (s) |')
print('|-------------|-------------------|-----------------|')

for metrics in all_metrics:
    env = metrics.get('environment', 'unknown')
    config_time = metrics.get('config_response_time', 'N/A')
    log_time = metrics.get('log_response_time', 'N/A')
    config_str = f'{config_time:.3f}' if isinstance(config_time, float) else str(config_time)
    log_str = f'{log_time:.3f}' if isinstance(log_time, float) else str(log_time)
    print(f'| {env.title()} | {config_str} | {log_str} |')

print('')
print('## Environment Status')
print('')

for metrics in all_metrics:
    env = metrics.get('environment', 'unknown')
    status = metrics.get('status', 'unknown')
    status_icon = '✅' if status == 'completed' else '❌' if status == 'failed' else '⏳'
    print(f'- **{env.title()}**: {status_icon} {status.title()}')

print('')
print('## Analysis')
print('')

# Calculate overall success rate
total_envs = len(all_metrics)
successful_envs = sum(1 for m in all_metrics if m.get('status') == 'completed' and m.get('failed_tests', 0) == 0)
overall_success_rate = (successful_envs / total_envs * 100) if total_envs > 0 else 0

print(f'- **Overall Success Rate**: {overall_success_rate:.1f}% ({successful_envs}/{total_envs} environments)')

# Performance analysis
config_times = [m.get('config_response_time') for m in all_metrics if isinstance(m.get('config_response_time'), float)]
log_times = [m.get('log_response_time') for m in all_metrics if isinstance(m.get('log_response_time'), float)]

if config_times:
    fastest_config = min(config_times)
    slowest_config = max(config_times)
    print(f'- **Configuration Service**: Fastest {fastest_config:.3f}s, Slowest {slowest_config:.3f}s')

if log_times:
    fastest_log = min(log_times)
    slowest_log = max(log_times)
    print(f'- **Log Aggregator Service**: Fastest {fastest_log:.3f}s, Slowest {slowest_log:.3f}s')

print('')
print('## Recommendations')
print('')

# Generate recommendations based on results
if successful_envs == total_envs:
    print('🎉 **All environments passed successfully!**')
    print('')
    print('- The microservices architecture is working correctly across all deployment scenarios')
    print('- Performance is consistent between environments')
    print('- Ready for production deployment')
else:
    print('⚠️  **Some environments have issues that need attention:**')
    print('')
    for metrics in all_metrics:
        if metrics.get('status') != 'completed' or metrics.get('failed_tests', 0) > 0:
            env = metrics.get('environment', 'unknown')
            print(f'- **{env.title()}**: Review failed tests and address issues')

print('')
print('## Next Steps')
print('')
print('1. Review individual environment reports for detailed information')
print('2. Address any failing tests before production deployment')
print('3. Consider performance optimization if response times are high')
print('4. Use this baseline for future regression testing')

" >> $COMPARISON_REPORT 2>/dev/null || echo "Could not generate detailed comparison"

# Update unified results with comparison data
python3 -c "
import json

try:
    with open('$UNIFIED_REPORT', 'r') as f:
        data = json.load(f)
    
    # Calculate overall status
    statuses = []
    for env in data['environments'].values():
        statuses.append(env.get('status', 'unknown'))
    
    if all(s == 'passed' for s in statuses):
        overall_status = 'all_passed'
    elif any(s == 'passed' for s in statuses):
        overall_status = 'partial_success'
    else:
        overall_status = 'all_failed'
    
    data['overall_status'] = overall_status
    data['summary'] = {
        'total_environments': len(statuses),
        'passed_environments': sum(1 for s in statuses if s == 'passed'),
        'failed_environments': sum(1 for s in statuses if s == 'failed')
    }
    
    with open('$UNIFIED_REPORT', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    pass
" 2>/dev/null || true

# Display final results
echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}Final Results Summary${NC}"
echo -e "${CYAN}========================================${NC}"

# Show environment results
echo -e "\n${BLUE}Environment Results:${NC}"
if [ $DEV_RESULT -eq 0 ]; then
    echo -e "• Development: ${GREEN}✅ PASSED${NC}"
else
    echo -e "• Development: ${RED}❌ FAILED${NC}"
fi

if [ $ACT_RESULT -eq 0 ]; then
    echo -e "• GitHub Actions (act): ${GREEN}✅ PASSED${NC}"
else
    echo -e "• GitHub Actions (act): ${RED}❌ FAILED${NC}"
fi

if [ $K8S_RESULT -eq 0 ]; then
    echo -e "• Kubernetes: ${GREEN}✅ PASSED${NC}"
else
    echo -e "• Kubernetes: ${RED}❌ FAILED${NC}"
fi

# Show overall result
TOTAL_FAILED=$((DEV_RESULT + ACT_RESULT + K8S_RESULT))
if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 ALL ENVIRONMENTS PASSED!${NC}"
    echo -e "${GREEN}The microservices are ready for production deployment.${NC}"
    OVERALL_RESULT=0
else
    echo -e "\n${RED}❌ $TOTAL_FAILED ENVIRONMENT(S) FAILED${NC}"
    echo -e "${YELLOW}Review failed tests and address issues before deployment.${NC}"
    OVERALL_RESULT=1
fi

# Show file locations
echo -e "\n${BLUE}📄 Reports Generated:${NC}"
echo -e "• Unified Report: ${CYAN}$UNIFIED_REPORT${NC}"
echo -e "• Comparison Report: ${CYAN}$COMPARISON_REPORT${NC}"
echo -e "• Individual Reports: ${CYAN}$RESULTS_DIR/*-test-report.json${NC}"

# Show comparison report summary
if [ -f "$COMPARISON_REPORT" ]; then
    echo -e "\n${BLUE}📊 Quick Comparison:${NC}"
    echo -e "${YELLOW}$(tail -n 10 $COMPARISON_REPORT | head -n 5)${NC}"
fi

# Recommendations
echo -e "\n${BLUE}💡 Recommendations:${NC}"
if [ $OVERALL_RESULT -eq 0 ]; then
    echo -e "• ${GREEN}All systems operational - ready for production${NC}"
    echo -e "• Use these results as baseline for future testing"
    echo -e "• Consider automating this test suite in CI/CD pipeline"
else
    echo -e "• ${YELLOW}Review failed test logs in $RESULTS_DIR/${NC}"
    echo -e "• Fix issues in failing environments"
    echo -e "• Re-run tests after addressing issues"
fi

echo -e "\n${BLUE}🚀 Next Steps:${NC}"
echo -e "• View detailed comparison: ${CYAN}cat $COMPARISON_REPORT${NC}"
echo -e "• Run individual environment: ${CYAN}make test-dev${NC} | ${CYAN}make test-act${NC} | ${CYAN}make test-k8s-local${NC}"
echo -e "• Deploy to production: ${CYAN}make k8s-deploy${NC} (after all tests pass)"

exit $OVERALL_RESULT