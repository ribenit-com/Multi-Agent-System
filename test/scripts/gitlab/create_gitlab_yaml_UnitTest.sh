#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成脚本单元测试
#########################################

EXEC_SCRIPT="gitlab_yaml_gen_UnitTest.sh"
TARGET_SCRIPT="gitlab_yaml_gen.sh"

EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/create_gitlab_yaml_UnitTest.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/create_gitlab_yaml.sh"

#########################################
# 下载脚本（如果不存在）
#########################################

download_if_missing() {
  local file="$1"
  local url="$2"
  if [ ! -f "$file" ]; then
    echo "⬇️ Downloading $file ..."
    curl -f -L "$url" -o "$file"
    chmod +x "$file"
  fi
}

download_if_missing "$EXEC_SCRIPT" "$EXEC_URL"
download_if_missing "$TARGET_SCRIPT" "$TARGET_URL"

#########################################
# UT 断言工具
#########################################

fail() { echo "❌ FAIL: $1"; exit 1; }
pass() { echo "✅ PASS"; }
assert_file_exists() { [ -f "$1" ] || fail "File $1 not found"; pass; }
assert_file_contains() { grep -q "$2" "$1" || fail "File $1 does not contain '$2'"; pass; }
assert_equal() { [[ "$1" == "$2" ]] || fail "expected=$1 actual=$2"; pass; }

#########################################
# 测试环境准备
#########################################

TEST_DIR=$(mktemp -d)
MODULE="GitLab_Test"

export HOME="$TEST_DIR"

#########################################
# 运行目标脚本生成 YAML
#########################################

bash "$TARGET_SCRIPT" "$MODULE" "$TEST_DIR" "ns-test-gitlab" "sc-fast" "50Gi" "gitlab/gitlab-ce:15.0" "gitlab.test.local" "192.168.50.10" "35050" "30022" "30080"

#########################################
# UT 测试
#########################################

# UT-04 Namespace YAML
assert_file_exists "$TEST_DIR/${MODULE}_namespace.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "apiVersion: v1"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "name: ns-test-gitlab"

# UT-05 Secret YAML
assert_file_exists "$TEST_DIR/${MODULE}_secret.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_secret.yaml" "root-password"

# UT-06 StatefulSet YAML
assert_file_exists "$TEST_DIR/${MODULE}_statefulset.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "volumeClaimTemplates"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"

# UT-07 Service YAML
assert_file_exists "$TEST_DIR/${MODULE}_service.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30080"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30022"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 35050"

# UT-08 CronJob YAML
assert_file_exists "$TEST_DIR/${MODULE}_cronjob.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "registry-garbage-collect"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "persistentVolumeClaim"

# UT-09 YAML 格式验证（kubectl dry-run）
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_namespace.yaml" >/dev/null 2>&1 && pass || fail "Namespace YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_secret.yaml" >/dev/null 2>&1 && pass || fail "Secret YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_statefulset.yaml" >/dev/null 2>&1 && pass || fail "StatefulSet YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_service.yaml" >/dev/null 2>&1 && pass || fail "Service YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_cronjob.yaml" >/dev/null 2>&1 && pass || fail "CronJob YAML invalid"

# UT-10 输出提示
EXPECTED_OUTPUT="✅ GitLab YAML 已生成到 $TEST_DIR"
bash "$TARGET_SCRIPT" "$MODULE" "$TEST_DIR" | grep -q "$EXPECTED_OUTPUT" && pass || fail "Output missing expected text"

echo "🎉 All YAML generation tests passed (enterprise-level v1)"
