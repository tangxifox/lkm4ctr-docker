# 排错手册（实战记录）

按"现象 -> 根因 -> 解法"列出本项目实际踩过的全部坑。

## 1. mkdir /run: read-only file system（插件目录）

```
failed to start daemon: couldn't create plugin manager:
failed to mkdir /run/docker/plugins: mkdir /run: read-only file system
```

根因：dockerd 源码 getPluginExecRoot() 硬编码该路径（v24~v29 全部如此）。
解法：二进制补丁 /run/docker/plugins -> /data/docker/plugin。
排除：改 exec-root / data-root 无效；降级 docker 也无效。

## 2. shim 报 /run/containerd/s/<id>

```
failed to start shim: create new shim socket:
mkdir failed for /run/containerd/s/<hash>: mkdir /run: read-only file system
```

根因：新版 dockerd 不再向 containerd 传 --state，containerd/shim 各用默认 /run/containerd。
解法：补丁 /run/containerd -> /data/container（dockerd / containerd / shim 三个文件）。
注意：改 containerd 的 config.toml 的 state 只解决它自己，shim 仍用默认值。

## 3. 拉镜像 x509: certificate signed by unknown authority

根因：dockerd 是 Go 写的，只认 /etc/ssl/certs/ca-certificates.crt 等固定路径；
Android 根证书在 /system/etc/security/cacerts/，Go 不读。
解法：合并成 bundle 并指定 SSL_CERT_FILE：

```sh
mkdir -p /data/docker/ca
cat /system/etc/security/cacerts/* /data/misc/user/0/cacerts-added/* 2>/dev/null > /data/docker/ca/ca-certificates.crt
export SSL_CERT_FILE=/data/docker/ca/ca-certificates.crt
```

## 4. 拉镜像超时 Client.Timeout exceeded while awaiting headers

根因：所选 registry mirror 不可达（被墙 / 黑洞 / 失效）。
解法：换可达镜像源，或改用 HTTP 代理（HTTPS_PROXY）。可用：https://gh-proxy.org/docker

## 5. DNS: lookup registry-1.docker.io on [::1]:53: connection refused

根因：dockerd 读不到 /etc/resolv.conf 时退化为访问 127.0.0.1:53 / [::1]:53，
而 Android 本机没有 DNS 服务。daemon.json 的 "dns" 只注入容器，不管 daemon 自身。
解法：给系统补 resolv.conf（Magisk 模块提供 system/etc/resolv.conf，因为 /etc -> /system/etc）：

```
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 8.8.8.8
```

## 6. delete /data/docker/run/docker.pid: process with PID xxx is still running

根因：上次异常退出留下的 pidfile，或 PID 被复用。
解法：启动 dockerd 前清掉 pidfile（service.sh 已内置）。

## 7. dial unix .../containerd.sock: connect: connection refused

根因：containerd 进程已死，但 socket 文件还在（假活）。
解法：清掉残留 socket 再拉起 containerd；service.sh 已内置清理 + 等 socket 就绪。

## 8. invalid disabled plugin URI "cri" expect io.containerd.x.vx

根因：containerd 2.x 的 disabled_plugins 只接受完整插件 URI。
解法：删掉该行（CRI 加载失败只是 /etc/cni 只读警告，不影响 docker）。

## 9. nsexec-1: failed to unshare remaining namespaces: Invalid argument

根因：内核缺 PID/IPC/USER namespace —— lkm4ctr 模块没加载。
解法：

```sh
grep -c '^lkm4ctr ' /proc/modules      # 0 = 没加载
insmod /data/adb/modules/lkm4ctr-docker/lkm4ctr/lkm4ctr-<KMI>-arm64.ko
sh /data/adb/modules/lkm4ctr-docker/lkm4ctr/lkm4ctr_checker-arm64 | tail -1
```

## 10. 开机卡住 / service.sh 一行日志都不写

根因：Magisk 会等 service.sh 返回，而脚本开头等 sys.boot_completed，两者互等 -> 死锁。
解法：主体包进 `( ... ) &` 并 exit 0；insmod 等不依赖开机的动作放最前面。

## 11. insmod: ... File exists

根因：模块已加载（EEXIST），不是错误。
解法：先判断再加载：[ "$(grep -c '^lkm4ctr ' /proc/modules)" = "0" ] && insmod ...

## 12. Text file busy（打补丁时）

根因：目标二进制正在运行（ETXTBSY）。
解法：先停进程；必要时"复制到别处打完再 mv 回去"（rename 覆盖运行中的文件是允许的）。

## 13. Device or resource busy（删不掉 /data/docker）

根因：fuse-overlayfs 的 merged 挂载点与 netns bind mount 仍活跃。
解法：先停进程 -> 逆序 umount -l（见 tools/cleanup-docker.sh），或重启后再删。
