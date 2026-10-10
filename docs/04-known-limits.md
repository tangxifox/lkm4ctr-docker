# 已知限制

## 1. NET namespace 是记账式（STUB）

lkm4ctr 对 CLONE_NEWNET 只做"让调用成功返回"，namespace id 不变，没有真实网络隔离。

后果：

- 只能 --network=host，docker run -p 不会生效（bridge 与 NAT 规则建不起来）
- 容器内网络与宿主完全一致
- checker 中表现为 ns_net STUB

## 2. CGROUP namespace 是记账式（STUB）

没有 cgroup 控制器暴露，dockerd 启动会刷：

```
WARNING: No memory limit support
WARNING: No swap limit support
WARNING: No cpu cfs quota support
WARNING: No cpu shares support
WARNING: No cpuset support
WARNING: No io.weight support
```

后果：

- --memory / --cpus / --blkio-weight 全部不可用
- 容器内不能跑 systemd
- --cgroup-parent 无意义

## 3. / 只读

system-as-root，mount -o remount,rw / 通常失败，因此：

- 不能用"创建 /run"这种直觉解法
- 一切落点必须在 /data 下（或用 Magisk 模块覆盖 /system/*）

## 4. 存储性能

fuse-overlayfs 是用户态实现，小文件密集场景明显慢于内核 overlay2。
若在意性能，可在 /data 上放 ext4 镜像文件 loop 挂载（绕开 casefold 从而可用 overlay2），
但会引入"忘了挂载就启动失败"的新坑。

## 5. dockerd 需要可用的 /etc/resolv.conf

见 docs/03 第 5 条。不想补 resolv.conf 时，可让 dockerd 走 HTTP 代理（代理场景不需要本地 DNS）。

## 6. KMI 必须匹配

lkm4ctr 按 KMI 出包（android12-5.10 ... android16-6.12），不匹配无法加载。
模块会自动挑选对应文件，但上游必须存在该 KMI 的产物。

## 7. 卸载

有 hook 运行时 rmmod lkm4ctr 会被拒绝，只能重启；
卸载模块默认不删 /data/docker（见 REMOVE_DATA_ON_UNINSTALL）。
