# lkm4ctr-docker

Android（root + Magisk）上把完整 Docker 运行时装进 `/system` 的 Magisk 模块。

## 内容

```
module/                                模块主体（＝刷入后的文件结构）
├── module.prop
├── customize.sh                       安装时：权限 / KMI 识别 / 缺 ko 时下载
├── service.sh                         开机：insmod -> 建目录与 CA -> containerd -> dockerd
├── post-fs-data.sh                    只建目录
├── uninstall.sh
├── conf/
│   ├── daemon.json                    fuse-overlayfs / 外部 containerd / registry 镜像源
│   ├── containerd.toml                root 与 state 指向 /data
│   └── docker.conf                    开关（KO 来源、代理、自动下载等）
└── system/
    ├── docker                         CLI 包装脚本（自动设置 DOCKER_HOST）
    └── etc/resolv.conf                dockerd 的 DNS（Go 解析器必需）

build_lkm4ctr_docker_module.sh         生成器：识别 KMI、取 ko、给二进制打补丁、打包 zip
patch-docker-binaries.py               两个 /run 路径补丁（等长替换，自动备份 .orig）
```

## 两个二进制补丁

Android 的 `/` 只读，而 Docker 栈有三处写死 `/run`；其中两处无法用配置覆盖，必须在二进制里**等长替换**
（Go 的字符串不能补 NUL，否则 `syscall.BytePtrFromString` 返 EINVAL）：

```
/run/docker/plugins  (19B) -> /data/docker/plugin  (19B)    仅 dockerd，1 处
/run/containerd      (15B) -> /data/container      (15B)    dockerd 3 / containerd 3 / shim 2
```

第三处（containerd 自身 state）由 `module/conf/containerd.toml` 的 `state` 解决，无需补丁。

打补丁与校验：

```sh
python patch-docker-binaries.py /data/adb/modules/lkm4ctr-docker/system/bin

grep -c /data/docker/plugin /system/bin/dockerd                   # 1
grep -c /data/container     /system/bin/containerd                # 3
grep -c /data/container     /system/bin/containerd-shim-runc-v2   # 2
```

> Magisk 是开机 bind mount，改完必须重启。

## 生成与刷入

```sh
pkg install python zip curl -y
bash build_lkm4ctr_docker_module.sh          # 产物 ~/lkm4ctr-docker.zip
# Magisk App -> 模块 -> 从本地安装 -> 重启
```

生成器流程：检查 9 个二进制 -> 由 `uname -r` 识别 KMI -> 取 `lkm4ctr-<KMI>-arm64.ko`
-> 复制二进制到模块并在副本上打补丁 -> 写入脚本/配置/resolv.conf -> 打包。

## 注意

- 需 root + Magisk；内核 KMI 必须存在于上游 lkm4ctr Release
- NET / CGROUP 为记账式（STUB）：只能 `--network=host`，`-p`、`--memory`、`--cpus` 不可用
- 改动 `module/` 内文件后，重新跑生成器打包即可
