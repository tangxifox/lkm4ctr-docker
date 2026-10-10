# lkm4ctr-docker

在 Android（root + Magisk）上把完整 Docker 运行时装进 `/system`，
并依靠 [cyanmint/lkm4ctr](https://github.com/cyanmint/lkm4ctr) 树外内核模块补齐容器所需的命名空间。

无需重编内核、无需刷 system 分区。

## 组成

| 部分 | 内容 |
|---|---|
| Magisk 模块 | docker / dockerd / containerd / containerd-shim-runc-v2 / ctr / runc / docker-init / docker-proxy / fuse-overlayfs（全部静态链接） |
| 内核模块 | lkm4ctr-<KMI>-arm64.ko（vendored PID/USER/IPC ns、POSIX mqueue、SysV IPC）+ lkm4ctr_checker |
| 二进制补丁 | 两个等长替换，绕开 Android 只读 `/` 导致的 `/run` 路径失败，见 `docs/01-overview.md` |

## 快速开始

```sh
# 1) Termux 里生成模块（自动识别 KMI、下载 ko、给二进制打补丁、打包）
pkg install python zip curl -y
bash build/build_lkm4ctr_docker_module.sh
# 产物 ~/lkm4ctr-docker.zip

# 2) Magisk App -> 模块 -> 从本地安装 -> 重启

# 3) 验证
su
docker run --rm --network=host alpine uname -m       # 期望 aarch64
docker info | grep -i "storage driver"               # 期望 fuse-overlayfs
```

## 已验证环境

| 项 | 值 |
|---|---|
| 设备内核 | 6.1.75-android14-11-g...（KMI android14-6.1） |
| docker / containerd | 静态包 docker-29.9.0 · containerd v2.4.1 |
| 存储驱动 | fuse-overlayfs v1.18（`/data` 为 casefold F2FS，overlay2 不可用） |
| checker 结果 | 0 FAIL, 2 STUB (bookkeeping-only) |
| 实测 | 拉取 nginx:alpine、起容器、host 网络访问均正常 |

## 关键结论

1. `/run` 被硬编码三次，而 Android 的 `/` 只读 → 必须打补丁或用配置绕开
2. NET / CGROUP 是记账式（STUB）→ 只能 `--network=host`，端口映射与资源限制不可用
3. service.sh 必须丢后台，否则会和 sys.boot_completed 互相等死
4. dockerd 需要 `/etc/resolv.conf`，否则 Go 解析器会去问 `[::1]:53` 并 connection refused
5. containerd 2.x 的 disabled_plugins 只接受完整插件 URI，写 "cri" 会启动失败

## 目录

```
build/    生成器与补丁脚本（在 Termux 侧运行）
module/   模块内文件（脚本 + 配置 + resolv.conf），可直接对照/覆盖
tools/    设备与 Termux 侧的清理脚本
docs/     架构、安装、排错、限制、变更记录
notes/    上游来源与校验信息
dist/     产物（zip 与打好的二进制，体积大，不纳入 git）
```

## 不适用

- 无 root / 未装 Magisk 的设备
- 期望 `docker -p` 端口映射、`--memory`、`--cpus` 的场景
- 容器内跑 systemd 的场景（无 cgroup 隔离）
- 内核 KMI 不在上游 Release 里的设备

## 上游与致谢

- 内核模块：[cyanmint/lkm4ctr](https://github.com/cyanmint/lkm4ctr)
- fuse-overlayfs：[containers/fuse-overlayfs](https://github.com/containers/fuse-overlayfs) v1.18
- docker 静态二进制：download.docker.com/linux/static/stable/aarch64

来源与校验见 `notes/upstream.md`。
