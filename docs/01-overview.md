# 架构与核心问题

## 整体链路

```
Magisk 模块（/system/bin 提供二进制 + service.sh 开机编排）
        |
containerd（外部模式，root/state 指向 /data，socket 在 /data/docker/containerd）
        |
dockerd（daemon.json：fuse-overlayfs、containerd 外部 socket、registry 镜像源）
        |
runc + containerd-shim-runc-v2（shim socket 落在 /data/container）
        ^
lkm4ctr 内核模块（补 PID / USER / IPC ns、POSIX mqueue、SysV IPC）
```

## Android 的 / 是只读的 -> /run 用不了

Docker 栈里三处路径写死在 `/run` 下，而 Android 根目录（system-as-root）不可写：

| # | 位置 | 硬编码串 | 是否可配置 | 处理方式 |
|---|---|---|---|---|
| 1 | dockerd 插件目录 | /run/docker/plugins | 否（getPluginExecRoot() 直接 return 常量） | 二进制补丁 -> /data/docker/plugin |
| 2 | containerd 自身 state | /run/containerd | 是（config.toml 的 state） | 配置项解决 |
| 3 | runc shim socket | /run/containerd/s/<id> | 否（shim 进程自带默认） | 二进制补丁 -> /data/container |

第 1 处在 v24.0.9 ~ v29.x 全部写死（已逐版本核对），降级无效。

## 两个二进制补丁

必须严格等长替换：Go 的 syscall.BytePtrFromString 遇到内嵌 NUL 会返回 EINVAL，
所以不能补零凑长度，只能选长度一致的路径。

```
/run/docker/plugins   19 字节  ->  /data/docker/plugin   19 字节   （仅 dockerd，1 处）
/run/containerd       15 字节  ->  /data/container       15 字节   （dockerd 3 / containerd 3 / shim 2）
```

替换后运行时应存在：

```
/data/docker/plugin      dockerd 插件目录
/data/container/s/<id>   runc shim socket 基目录
/data/container/runc     旧式 shim 路径
```

脚本：`build/patch-docker-binaries.py`；也可直接用 `dist/*.patched`。

## 为什么用 fuse-overlayfs

`/data` 是 F2FS 且启用 casefold，内核 overlay2 在此类文件系统上挂载失败
（mount ... invalid argument）。因此 storage-driver 必须是 fuse-overlayfs
（用户态实现，性能低于内核 overlay2，但可用）。

## 为什么 containerd 要独立起

新版 dockerd 不再向 containerd 传 --state（二进制里 --state 出现 0 次），
containerd 使用默认 /run/containerd；即使 dockerd 的 exec-root 改到 /data，
shim 的 socket 仍然会落到 /run。

因此改为外部 containerd 模式：用 config.toml 指定 root / state / address，
dockerd 通过 daemon.json 的 "containerd" 字段连它。
