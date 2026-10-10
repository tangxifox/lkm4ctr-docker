# lkm4ctr-docker

> 在 Android（root + Magisk）上跑 Docker。不用重编内核，也不用刷 system 分区。

## 能做什么

- 正常拉镜像、起容器：`docker pull nginx:alpine`、`docker run -d --network=host nginx:alpine`
- 容器拥有真实的 PID / IPC / USER 命名空间，以及 POSIX 消息队列与 SysV IPC
- 把 `docker` `dockerd` `containerd` `containerd-shim-runc-v2` `ctr` `runc`
  `docker-init` `docker-proxy` `fuse-overlayfs` 一共 9 个二进制装进 `/system/bin`
- 开机自动完成：加载内核模块 → 建目录与 CA → 拉起 containerd → 拉起 dockerd
- 存储驱动用 `fuse-overlayfs`（因为 `/data` 是 casefold F2FS，内核 overlay2 挂不上）

**做不到**：`docker -p` 端口映射、`--memory` / `--cpus` 等资源限制（Network 与 cgroup 是记账式的），
容器里也跑不了 systemd。所以容器一律用 `--network=host`。


配置与开关在 `/data/adb/lkm4ctr-docker/docker.conf`，日志在同目录下的 `service.log`、
`containerd.log`、`dockerd.log`。

## 依赖的两个上游项目

- **lkm4ctr** —— 补齐容器所需的内核能力（命名空间、IPC）
  <https://github.com/cyanmint/lkm4ctr>
- **fuse-overlayfs** —— 在 casefold F2FS 上替代 overlay2 的存储驱动
  <https://github.com/containers/fuse-overlayfs>

## 许可与致谢

**本项目不单独声明许可；内核模块 lkm4ctr 的许可以上游仓库为准。**

- **lkm4ctr**（内核模块）：<https://github.com/cyanmint/lkm4ctr>
  上游未附 LICENSE 文件（默认保留所有权利），使用与分发请先确认上游声明。
- **fuse-overlayfs**（存储驱动）：Apache-2.0 · <https://github.com/containers/fuse-overlayfs>
- **Docker 静态二进制**：Apache-2.0 · <https://download.docker.com/linux/static/stable/aarch64/>

本仓库只包含 Magisk 模块文件、装配脚本与补丁脚本；内核模块产物（ko）不随仓库分发，
由 `build_lkm4ctr_docker_module.sh` 在构建时从上游 Release 获取。
