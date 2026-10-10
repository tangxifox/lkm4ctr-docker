# lkm4ctr-docker

> 在 **Android（root + Magisk）** 上把完整 Docker 运行时装进 `/system` 的 Magisk 模块。
> 不用重编内核，也不用刷 system 分区。

---

## 这是什么

Android 有 root 并不等于能跑 Docker。容器需要 PID / IPC / USER 等命名空间、POSIX 消息队列
和 SysV IPC，而手机厂商内核通常关掉了它们；同时 Android 的根目录是只读的，Docker 又有几处
硬编码的 `/run` 路径无处落脚。

这个模块把两件事一起解决：

| 问题 | 解法 |
|---|---|
| 内核能力缺失 | 加载 [`lkm4ctr`](https://github.com/cyanmint/lkm4ctr) 树外内核模块补齐命名空间与 IPC |
| `/run` 不可用 | 在 Docker 二进制里做**等长替换**，把三处硬编码路径挪到 `/data` |
| 存储驱动不可用 | `/data` 是 casefold F2FS，`overlay2` 挂不上 → 换 [`fuse-overlayfs`](https://github.com/containers/fuse-overlayfs) |

装完之后，`docker run` / `docker pull` 就能像在服务器上一样用。

---

## 依赖的上游项目

本项目只是"装配说明书"，真正干活的是这两个开源项目，请先去给它们点星：

### 1. lkm4ctr —— 内核模块

**<https://github.com/cyanmint/lkm4ctr>**

为 Android GKI 设备提供树外（out-of-tree）内核模块，补上容器所需的：

- `PID` / `USER` / `IPC` 命名空间的真实实现
- POSIX 消息队列（`mq_open` 等）
- SysV IPC（`msgget` / `semget` / `shmget`）
- 附带的 `lkm4ctr_checker-arm64` 可以逐项自检

> 模块产物按 **KMI** 出包（`android12-5.10` ~ `android16-6.12`），必须与你的内核匹配。
> 本仓库的生成器会自动从 `uname -r` 推断 KMI 并下载对应文件。

### 2. fuse-overlayfs —— 存储驱动

**<https://github.com/containers/fuse-overlayfs>**

FUSE 版 overlay 文件系统。因为 Android 的 `/data` 是带 casefold 的 F2FS，
内核 overlay2 无法在其上挂载（`mount ... invalid argument`），
所以 Docker 的 `storage-driver` 必须用 `fuse-overlayfs`。

> 本项目使用其官方 Release 的 `fuse-overlayfs-aarch64`（静态链接，Android 可直接运行）。

---

## 目录结构

```
lkm4ctr-docker/
├── module/                               模块主体（＝刷入后的文件结构）
│   ├── module.prop                       模块信息
│   ├── customize.sh                      安装时：设权限 / 识别 KMI / 缺 ko 时下载
│   ├── service.sh                        开机：insmod → 目录与 CA → containerd → dockerd
│   ├── post-fs-data.sh                   只建目录
│   ├── uninstall.sh
│   ├── conf/
│   │   ├── daemon.json                   fuse-overlayfs / 外部 containerd / registry 镜像源
│   │   ├── containerd.toml               root 与 state 指向 /data
│   │   └── docker.conf                   开关（KO 来源、代理、自动下载）
│   └── system/
│       ├── docker                        CLI 包装脚本，自动设置 DOCKER_HOST
│       ├── etc/resolv.conf               dockerd 的 DNS（Go 解析器必需）
│       └── bin/                          docker / dockerd / containerd / shim / ctr / runc
│                                         / docker-init / docker-proxy / fuse-overlayfs
├── build_lkm4ctr_docker_module.sh        生成器：取 ko、打补丁、打包 zip
└── patch-docker-binaries.py              两个 /run 路径补丁
```

---

## 两个二进制补丁（为什么必须）

Android 的 `/` 只读，`mount -o remount,rw /` 通常也会失败，所以 `/run` 根本建不出来。
而 Docker 栈里有三处路径写死在 `/run`：

| # | 位置 | 能否用配置改 | 处理 |
|---|---|---|---|
| 1 | dockerd 插件目录 `/run/docker/plugins` | **不能**（源码里直接 return 常量） | 打补丁 |
| 2 | containerd 自身 state `/run/containerd` | 可以（`containerd.toml` 的 `state`） | 改配置 |
| 3 | runc shim socket `/run/containerd/s/<id>` | **不能**（shim 进程自带默认值） | 打补丁 |

补丁是**严格等长**的字节替换，因为 Go 的字符串不能含 NUL
（`syscall.BytePtrFromString` 遇到内嵌 NUL 会返回 `EINVAL`）：

```
/run/docker/plugins  (19B) ──▶ /data/docker/plugin  (19B)     仅 dockerd，1 处
/run/containerd      (15B) ──▶ /data/container      (15B)     dockerd 3 / containerd 3 / shim 2
```

打补丁（会自动把原文件备份成 `.orig`）：

```sh
python patch-docker-binaries.py /data/adb/modules/lkm4ctr-docker/system/bin
```

校验是否生效（Magisk 是开机 bind mount，**改完必须重启**）：

```sh
grep -c /data/docker/plugin /system/bin/dockerd                   # 期望 1
grep -c /data/container     /system/bin/containerd                # 期望 3
grep -c /data/container     /system/bin/containerd-shim-runc-v2   # 期望 2
```

---

## 安装

### 1. 生成模块（在 Termux 里）

```sh
pkg install python zip curl -y
bash build_lkm4ctr_docker_module.sh
# 产物：~/lkm4ctr-docker.zip
```

生成器会：检查 9 个二进制 → 由 `uname -r` 识别 KMI → 取 `lkm4ctr-<KMI>-arm64.ko`
→ 复制二进制并对副本打补丁 → 写入脚本/配置/`resolv.conf` → 打包。

可选环境变量：

```sh
PROXY=http://172.16.0.254:8000     # HTTP 代理
GH_PROXY=https://gh-proxy.com      # GitHub 加速前缀，留空直连
BIN_DIR=$PREFIX/bin                # 二进制来源目录
```

### 2. 刷入

Magisk App → 模块 → 从本地安装 → 选 `lkm4ctr-docker.zip` → **重启**。

> 若 `/data/docker/daemon.json` 或 `/data/docker/containerd/config.toml` 已存在，
> 安装脚本不会覆盖它们，需要手动删除旧文件或自行合并新键。

### 3. 验证

```sh
su

grep -c '^lkm4ctr ' /proc/modules                 # 1 —— 内核模块已加载
ls -l /data/docker/run/docker.sock                # socket 存在

docker info | grep -i "storage driver"            # fuse-overlayfs
docker run --rm --network=host alpine uname -m    # aarch64
```

想额外确认 PID 命名空间真的生效：

```sh
docker run --rm --network=host alpine sh -c 'echo pid1=$(cat /proc/1/comm)'
# 输出 pid1=sh（而不是宿主的 init）即为正确
```

---

## 日常使用

```sh
# 起容器：必须用 host 网络
docker run -d --name web --network=host nginx:alpine

# 一次性容器加 --rm，省得留垃圾
docker run --rm --network=host alpine uname -m

# 开机脚本手动触发一次（幂等）
sh /data/adb/modules/lkm4ctr-docker/service.sh

# 服务控制
pkill dockerd; pkill containerd-shim-runc-v2; pkill 'containerd --config'
```

配置开关在 `/data/adb/lkm4ctr-docker/docker.conf`：

```sh
LOAD_KO=1                 # 是否开机 insmod
START_DOCKER=1            # 是否开机拉起 containerd + dockerd
PROXY=                    # dockerd 出网代理，例 http://172.16.0.254:8000
AUTO_DOWNLOAD_KO=1        # 安装时缺 ko 是否自动下载
KO_TAG=                   # 锁定 Release 版本，留空跟随最新
GH_PROXY=https://gh-proxy.com
```

---

## 已知限制

1. **NET 命名空间是记账式** —— 只能 `--network=host`，`docker -p` 端口映射**不可用**
2. **CGROUP 命名空间是记账式** —— `--memory` / `--cpus` / `--blkio-weight` 全部不可用，
   容器内也**跑不了 systemd**
3. **存储性能** —— `fuse-overlayfs` 是用户态实现，小文件密集场景慢于内核 overlay2
4. **KMI 必须匹配** —— 上游没有对应 KMI 的产物就无法加载
5. **dockerd 需要 `/etc/resolv.conf`** —— 否则 Go 解析器会去问 `[::1]:53` 并 `connection refused`
   （模块已自带 `system/etc/resolv.conf`）

---

## 排错速查

| 现象 | 根因 / 解法 |
|---|---|
| `mkdir /run: read-only file system`（插件目录） | 补丁未生效，或没重启 |
| shim 报 `/run/containerd/s/<id>` | 同上，检查 shim 的补丁 |
| `nsexec-1: failed to unshare remaining namespaces: Invalid argument` | 内核模块没加载 → `insmod`，再跑 checker 应为 `0 FAIL` |
| `x509: certificate signed by unknown authority` | 缺 CA bundle → 合并 `/system/etc/security/cacerts/*` 并设 `SSL_CERT_FILE` |
| `lookup ... on [::1]:53: connection refused` | 缺 `/etc/resolv.conf` |
| `delete /data/docker/run/docker.pid: process with PID xxx is still running` | 残留 pidfile → 启动前清理 |
| `dial unix .../containerd.sock: connection refused` | containerd 已死但 socket 还在 → 清 socket 后重建 |
| `invalid disabled plugin URI "cri"` | containerd 2.x 只接受完整插件 URI → 删掉该行 |
| 开机卡住、`service.sh` 无日志 | 脚本主体必须丢后台，避免与 `sys.boot_completed` 死锁 |

---

## 卸载

```sh
# Magisk 里停用/删除模块后重启即可；
# 数据默认保留在 /data/docker，如需清空：
rm -rf /data/docker /data/container /data/adb/lkm4ctr-docker
```

有 hook 运行时 `rmmod lkm4ctr` 会被拒绝，只能重启。

---

## 许可与致谢

- **lkm4ctr**：<https://github.com/cyanmint/lkm4ctr>（内核模块，遵循其仓库声明）
- **fuse-overlayfs**：<https://github.com/containers/fuse-overlayfs>（Apache-2.0）
- Docker 静态二进制：<https://download.docker.com/linux/static/stable/aarch64/>

本仓库只包含 Magisk 模块文件、装配脚本与补丁脚本。
