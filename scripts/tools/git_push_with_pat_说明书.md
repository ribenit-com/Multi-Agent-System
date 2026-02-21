
使用方法

保存为 git_push_with_pat.sh

给执行权限：

chmod +x git_push_with_pat.sh

执行上传（可指定分支和 commit 信息）：

./git_push_with_pat.sh            # 默认 main 分支，自动生成 commit 信息
./git_push_with_pat.sh dev "更新 dev 分支内容"

✅ 特点：

跨平台安全：macOS/Windows 用系统安全存储，Linux 临时缓存，避免明文存储 PAT

自动检测远程可访问性

自动 add/commit/push，一次执行完成
