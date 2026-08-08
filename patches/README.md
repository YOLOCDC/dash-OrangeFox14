# patches/

可选：把构建时需要在 OrangeFox/AOSP 源码上应用的补丁放在这里
（`git format-patch` / `git diff` 输出，路径相对 OrangeFox 根，例如
`bootable/recovery/minuitwrp/events.cpp`）。

CI（`.github/workflows/build.yml`）在 sync 之后按文件名顺序 `git apply`
本目录所有 `*.patch`。没有本目录时 CI 构建未打补丁的官方源码（可用，
但缺少 README "Source boundary" 中列出的功能补丁，如 EV_FF 触觉）。

实机验证的 r46 构建依赖以下外部源码例外（见 README "Source boundary"）：

- `bootable/recovery/minuitwrp/events.cpp` — EV_FF 触觉后端
- `bootable/recovery/gui/slidervalue.cpp` — 滑块触觉预览

从构建机导出（在 fox_14.1 根目录执行）：

```bash
git -C bootable/recovery diff minuitwrp/events.cpp gui/slidervalue.cpp \
  > patches/0001-recovery-haptics-events.patch
```

注意：OrangeFox 为 GPL-3.0 —— 公开发布打过补丁的 OrangeFox 源码时，
补丁也必须公开（放本目录即满足）。
