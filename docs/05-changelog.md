# 变更记录

## v1 初版
- 首次把 docker 静态二进制 + lkm4ctr ko 打包成 Magisk 模块
- 发现 /run/docker/plugins 硬编码 -> 首次二进制补丁
- 发现 containerd state 可用 config.toml 覆盖 -> 外部 containerd 模式

## v2 补丁与顺序
- 补上遗漏的 containerd-shim-runc-v2（否则容器无法启动）
- 补丁扩展为两个：/run/docker/plugins、/run/containerd
- 开机顺序改为 insmod -> containerd -> dockerd

## v3 精简
- 移除 docker-ko / docker-ctl / docker-ca-refresh 等自定义命令
- docker 保留为包装脚本（自动设 DOCKER_HOST），官方本体改名 docker-real
- ko 的 KMI 识别与下载改到安装时（customize.sh），运行时不下载

## v4 启动可靠性
- service.sh 主体丢后台，修掉与 sys.boot_completed 的死锁
- 启动前清理残留 socket / pidfile
- 拉起 dockerd 前等待 containerd socket 就绪
- insmod 改为绝对路径且在脚本最前面

## v5 网络与配置
- daemon.json 增加 registry-mirrors: https://gh-proxy.org/docker
- ko 下载走 https://gh-proxy.com 加速前缀（可留空直连）
- 修正 containerd.toml：删除非法的 disabled_plugins = ["cri"]
- 新增 system/etc/resolv.conf，解决 dockerd 的 DNS 解析失败

## 验证基准

```
checker       0 FAIL, 2 STUB
docker info   Storage Driver: fuse-overlayfs
docker run    --network=host nginx:alpine -> HTTP 200
```
