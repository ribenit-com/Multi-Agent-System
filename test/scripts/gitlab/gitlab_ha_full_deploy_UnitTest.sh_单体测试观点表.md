# check_gitlab_names_json.sh 单体测试观点表

| 编号 | 函数 | 场景 | 期望 |
|------|------|------|------|
| UT-01 | check_namespace | namespace 不存在 | error |
| UT-02 | check_namespace | enforce 模式 | warning |
| UT-03 | check_service | service 不存在 | error |
| UT-04 | check_pvc | pvc 命名不规范 | warning |
| UT-05 | check_pod | pod 非 Running | error |
| UT-06 | calculate_summary | 有 error | error |
| UT-07 | calculate_summary | 仅 warning | warning |
| UT-08 | calculate_summary | 无异常 | ok |


cat > UNIT_TEST_USAGE.md <<'EOF'
# check_gitlab_names_json.sh 单体测试使用说明

============================================================

一、目录结构

project/
├── check_gitlab_names_json.sh
├── test_check_gitlab.sh
└── UNIT_TEST_VIEW_TABLE.md

============================================================

二、测试目标

1. 每个检查函数可单独测试
2. calculate_summary 汇总逻辑可单独验证
3. 不依赖真实 Kubernetes 集群
4. 不执行 main 流程
5. 通过 mock kubectl 实现隔离

============================================================

三、测试核心原理

1）通过 source 加载脚本（不会执行 main）

    source ./check_gitlab_names_json.sh

主脚本使用入口隔离：

    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        main "$@"
    fi

------------------------------------------------------------

2）覆盖 kctl 函数（替代 kubectl）

主脚本中：

    kctl() {
        kubectl "$@"
    }

测试中覆盖：

    kctl() {
        mock_kctl "$@"
    }

这样所有 kubectl 调用都会进入 mock。

------------------------------------------------------------

3）每个测试前必须清空

    json_entries=()

否则会污染测试结果。

============================================================

四、运行测试

增加执行权限：

    chmod +x test_check_gitlab.sh

执行：

    ./test_check_gitlab.sh

成功示例：

    ✅ PASS
    ✅ PASS
    ✅ PASS
    🎉 All tests passed

失败示例：

    ❌ FAIL: expected=error actual=ok

============================================================

五、新增测试用例步骤

示例：测试 Pod Pending 返回 error

步骤 1：修改 mock_kctl

    *"get pods --no-headers"*)
        echo "gitlab-xxx 1/1 Pending 0 1m"
        ;;

步骤 2：增加测试代码

    json_entries=()
    check_pod
    result=$(calculate_summary)
    assert_equal "error" "$result"

============================================================

六、观点表对应关系

UT-01  check_namespace  namespace 不存在 → error
UT-02  check_namespace  enforce 模式 → warning
UT-03  check_service    service 不存在 → error
UT-04  check_pvc        pvc 命名错误 → warning
UT-05  check_pod        pod 非 Running → error
UT-06  calculate_summary 有 error → error
UT-07  calculate_summary 仅 warning → warning
UT-08  calculate_summary 无异常 → ok

============================================================

七、CI 集成示例

script:
  - chmod +x test_check_gitlab.sh
  - ./test_check_gitlab.sh

============================================================

八、设计原则

1. 每个函数单独测试
2. 不依赖真实环境
3. 不执行 main
4. 不使用外部框架
5. 不修改生产逻辑
6. 通过函数覆盖实现 mock

============================================================

文档版本：v1.0
适用脚本：check_gitlab_names_json.sh

EOF
