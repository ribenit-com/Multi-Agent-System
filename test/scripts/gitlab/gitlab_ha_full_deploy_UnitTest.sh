#!/bin/bash
# ===================================================
# HeliosGuard Unit Test
# 文件: gitlab_ha_full_deploy_UnitTest.sh
# 目的:
#   - 对 HeliosGuard v4.0 做单体测试
#   - Mock kubectl
#   - 不依赖真实集群
#   - 可用于 CI Pipeline
# ===================================================

set -euo pipefail

SCRIPT_UNDER_TEST="./gitlab_ha_full_deploy.sh"

PASS_COUNT=0
FAIL_COUNT=0

# ===================================================
# 测试工具函数
# ===================================================

pass() {
  echo "[PASS] $1"
  PASS_COUNT=$((PASS_COUNT+1))
}

fail() {
  echo "[FAIL] $1"
  FAIL_COUNT=$((FAIL_COUNT+1))
}

assert_contains() {
  local output="$1"
  local expected="$2"
  local case_name="$3"

  if echo "$output" | grep -q "$expected"; then
    pass "$case_name"
  else
    fail "$case_name"
    echo "Expected: $expected"
    echo "Actual Output:"
    echo "$output"
  fi
}

# ===================================================
# Mock kubectl
# ===================================================
# 通过覆盖 PATH 优先级实现 kubectl Mock
# ===================================================

setup_mock() {
  mkdir -p ./mockbin

  cat <<'EOF' > ./mockbin/kubectl
#!/bin/bash

# 模拟不同测试场景
case "$MOCK_SCENARIO" in

  namespace_missing)
    if [[ "$1" == "get" && "$2" == "ns" ]]; then
      exit 1
    fi
    ;;

  service_missing)
    if [[ "$3" == "get" && "$4" == "svc" ]]; then
      exit 1
    fi
    ;;

  pvc_invalid)
    if [[ "$3" == "get" && "$4" == "pvc" ]]; then
      echo "wrong-pvc-name"
      exit 0
    fi
    ;;

  pod_unhealthy)
    if [[ "$3" == "get" && "$4" == "pods" ]]; then
      echo "pod-1 Pending"
      exit 0
    fi
    ;;

  all_ok)
    exit 0
    ;;

esac

exit 0
EOF

  chmod +x ./mockbin/kubectl
  export PATH="$(pwd)/mockbin:$PATH"
}

cleanup_mock() {
  rm -rf ./mockbin
}

# ===================================================
# 测试用例
# ===================================================

test_namespace_missing_audit() {
  export MOCK_SCENARIO="namespace_missing"
  output=$(bash "$SCRIPT_UNDER_TEST" prod audit || true)
  assert_contains "$output" '"status":"error"' "Namespace Missing (Audit)"
}

test_namespace_missing_enforce() {
  export MOCK_SCENARIO="namespace_missing"
  output=$(bash "$SCRIPT_UNDER_TEST" prod enforce || true)
  assert_contains "$output" '"warning_count":1' "Namespace Missing (Enforce)"
}

test_service_missing() {
  export MOCK_SCENARIO="service_missing"
  output=$(bash "$SCRIPT_UNDER_TEST" prod audit || true)
  assert_contains "$output" '"severity":"error"' "Service Missing"
}

test_pvc_invalid() {
  export MOCK_SCENARIO="pvc_invalid"
  output=$(bash "$SCRIPT_UNDER_TEST" prod audit || true)
  assert_contains "$output" '"severity":"warning"' "PVC Naming Invalid"
}

test_pod_unhealthy() {
  export MOCK_SCENARIO="pod_unhealthy"
  output=$(bash "$SCRIPT_UNDER_TEST" prod audit || true)
  assert_contains "$output" '"severity":"error"' "Pod Unhealthy"
}

test_all_ok() {
  export MOCK_SCENARIO="all_ok"
  output=$(bash "$SCRIPT_UNDER_TEST" prod audit || true)
  assert_contains "$output" '"status":"ok"' "All Healthy"
}

# ===================================================
# 执行测试
# ===================================================

main() {
  setup_mock

  echo "=================================="
  echo "Running HeliosGuard Unit Tests"
  echo "=================================="

  test_namespace_missing_audit
  test_namespace_missing_enforce
  test_service_missing
  test_pvc_invalid
  test_pod_unhealthy
  test_all_ok

  cleanup_mock

  echo "=================================="
  echo "Test Summary"
  echo "=================================="
  echo "PASS: $PASS_COUNT"
  echo "FAIL: $FAIL_COUNT"

  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

main
