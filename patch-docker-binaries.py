#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给 docker 全家桶打 /run 路径补丁（等长替换，改完不影响文件结构与长度）

两个补丁（长度必须严格相等，Go 字符串不能补 NUL）：
    /run/docker/plugins   19 字节  ->  /data/docker/plugin   19 字节   （dockerd 插件目录）
    /run/containerd       15 字节  ->  /data/container       15 字节   （containerd/shim 的 state 基址）

用法（Termux）：
    pkg install python -y
    python patch-docker-binaries.py                                  # 默认打模块目录
    python patch-docker-binaries.py $PREFIX/bin                      # 打 Termux 里的副本
    python patch-docker-binaries.py /data/adb/modules/lkm4ctr-docker/system/bin
打完重启一次生效（Magisk 是开机 bind mount）。
"""
import hashlib
import os
import shutil
import sys

PATCHES = [
    (b'/run/docker/plugins', b'/data/docker/plugin'),   # 19 = 19
    (b'/run/containerd',     b'/data/container'),       # 15 = 15
]
TARGETS = ['dockerd', 'containerd', 'containerd-shim-runc-v2']


def main() -> int:
    target_dir = sys.argv[1] if len(sys.argv) > 1 else \
        '/data/adb/modules/lkm4ctr-docker/system/bin'

    for old, new in PATCHES:
        assert len(old) == len(new), ('长度不等，拒绝执行', old, new)

    print(f'目标目录: {target_dir}')
    changed = 0
    for name in TARGETS:
        path = os.path.join(target_dir, name)
        if not os.path.exists(path):
            print(f'  跳过 {name}（不存在）')
            continue
        data = open(path, 'rb').read()
        hits = 0
        for old, new in PATCHES:
            n = data.count(old)
            if n:
                data = data.replace(old, new)
                hits += n
        if hits == 0:
            print(f'  {name}: 已是补丁状态')
            continue
        if not os.path.exists(path + '.orig'):
            shutil.copy2(path, path + '.orig')
        with open(path, 'wb') as f:
            f.write(data)
        sha = hashlib.sha256(data).hexdigest()[:16]
        print(f'  {name}: 替换 {hits} 处  sha256={sha}')
        changed += 1

    print(f'完成，改动 {changed} 个文件；重启后生效')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
