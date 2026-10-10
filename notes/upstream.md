# 上游来源与校验

## 内核模块

- 仓库：https://github.com/cyanmint/lkm4ctr
- 使用版本：4.0.3（另有 lkm4ctr_checker-arm64）
- 产物命名：lkm4ctr-<KMI>-arm64.ko

| 内核版本 | KMI |
|---|---|
| 5.10.x-android12 | android12-5.10 |
| 5.10.x-android13 | android13-5.10 |
| 5.15.x-android13 | android13-5.15 |
| 5.15.x-android14 | android14-5.15 |
| 6.1.x-android14 | android14-6.1 |
| 6.6.x-android15 | android15-6.6 |
| 6.12.x-android16 | android16-6.12 |

KMI 推导：KMI = androidNN（来自 uname -r 的 tag）+ major.minor（来自版本前缀）
例：6.1.75-android14-11-gxxxx -> android14-6.1

设备侧首次构建时记录：

```
lkm4ctr-android14-6.1-arm64.ko   10,880,768 字节
lkm4ctr_checker-arm64               850,584 字节
```

## fuse-overlayfs

- 仓库：https://github.com/containers/fuse-overlayfs
- 版本：v1.18
- 资产：fuse-overlayfs-aarch64（与官方 SHA256SUMS 一致）

```
大小    1,549,296 字节
sha256  82fed736197b2a881a822e5357b488796f654e8371ce8573a1592331510a0133
```

链接方式：statically linked（无 INTERP），Android 可直接执行。

## docker 静态二进制

- 官方：https://download.docker.com/linux/static/stable/aarch64/
- 国内镜像：https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/aarch64/
- 使用版本：docker-29.9.0.tgz
- 包内：docker / dockerd / containerd / containerd-shim-runc-v2 / ctr / runc / docker-init / docker-proxy

## 加速与镜像

| 用途 | 地址 |
|---|---|
| GitHub 加速前缀 | https://gh-proxy.com/ |
| Docker 镜像源 | https://gh-proxy.org/docker |
| 内网 HTTP 代理 | http://172.16.0.254:8000 |

## 补丁校验

```sh
grep -c /data/docker/plugin /system/bin/dockerd                     # 1
grep -c /data/container     /system/bin/dockerd                     # 3
grep -c /data/container     /system/bin/containerd                  # 3
grep -c /data/container     /system/bin/containerd-shim-runc-v2     # 2
```
