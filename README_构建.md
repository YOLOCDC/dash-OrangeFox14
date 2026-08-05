# dash OrangeFox 14.1 构建指南

## 环境要求
- **OS**: Ubuntu 22.04 或更新（WSL2 也可）
- **内存**: 建议 16GB+（OrangeFox AOSP 构建较吃内存）
- **磁盘**: 至少 85GB 可用空间（fox_14.1 树）
- **工具链**:
  - JDK 17（`sudo apt install openjdk-17-jdk`）
  - repo（`curl https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo && chmod +x ~/bin/repo`）
  - 基础依赖：`sudo apt install git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 libncurses-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig python3 bc cpio ccache`

## 前置：同步 OrangeFox 14.1 源码树
用官方 sync 脚本（自动完成框架 overlay：build/make 补丁 + vendor/twrp
BoardConfigSoong.mk 注入 + system/vold weaver 补丁 + vendor/recovery）：

```bash
git clone https://gitlab.com/OrangeFox/sync.git
cd sync
./orangefox_sync.sh --branch 14.1 --path ~/fox_14.1
```

同步完成后 `~/fox_14.1/device/xiaomi/` 已存在，把本设备树放进去：

```bash
mkdir -p ~/fox_14.1/device/xiaomi/dash
# 将本仓库内容复制到 device/xiaomi/dash/（或 git clone）
```

参考 dali 的 README：https://github.com/localhosts-A/device_xiaomi_dali_twrp

## 构建步骤（release 路径）
```bash
cd ~/fox_14.1/device/xiaomi/dash
bash build.sh        # 一键：envsetup + lunch + installclean + vendorbootimage + package-vendor-boot.sh
```

手动步骤：
```bash
cd ~/fox_14.1
source build/envsetup.sh
lunch twrp_dash-ap2a-eng
m installclean
m vendorbootimage
bash device/xiaomi/dash/package-vendor-boot.sh ~/fox_14.1 ~/fox_14.1/vendor_boot-dash-<tag>.img
```

`package-vendor-boot.sh` 会校验 platform ramdisk/DTB/模块/分片布局/AVB footer，
产物 = `vendor_boot-dash-<tag>.img` + `.sha256`。

⚠️ 不要使用旧版 `build.sh` 精简步骤 / `build-variant.sh` / `mkbootimg-wrapper.sh`
的硬编码路径（已移除或改为相对路径）；删除集与 release 路径不一致。

## CI
GitHub Actions：
- `.github/workflows/build.yml` —— 完整构建 + **提取 F1**（workflow_dispatch /
  push main）。标准 ubuntu-22.04 runner（内置 slimhub 清理 + 24G swap，与
  TWRP-Recovery-Builder-2024 同款方案）。可选 `patches/*.patch` 复现 EV_FF
  触觉补丁。
- **CI 不打包最终 vendor_boot**（一次构建 1.5h+，不适合试打包参数）——
  artifact = `recovery-fragment.cpio.gz`（F1）+ built vendor_boot.img 备查。
- 本地组装（原厂 F0 + CI F1 + AVB）：
  ```bash
  bash device/xiaomi/dash/package-vendor-boot.sh ~/fox_14.1 ~/out.img ~/recovery-fragment.cpio.gz
  ```
- `.github/workflows/verify.yml` —— 快速自检（push/PR 触发）：shell 语法、
  prebuilt 哈希与脚本常量交叉校验、cmdline 一致性、脚本可执行位。

## 分区/格式说明（dash）
- 刷入: `fastboot flash vendor_boot <img>`
- vendor_boot v4, 64MB
- cmdline: `bootopt=64S3,32N2,64N2`（无 erofs；stock 实锤，package 脚本终检
  按此校验）
- 地址: ka 0x80000000 / ra 0xa6f00000 / tags 0x87c80000
- 双 gzip（platform + recovery），recovery 用 gzip 已在 dash 实测可进 REC

## prebuilt 说明
- `prebuilt/dtb/dash.dtb` = dash 官方 vendor_boot 的 DTB
- `prebuilt/recovery_modules/*.ko` = dash 恢复模式触摸模块（Novatek 三件套）
- `prebuilt/recovery_properties/*.prop` = dash 官方 build.prop
- `prebuilt/vendor_ramdisk/platform.cpio.gz` = **dash 官方完整 platform ramdisk（gzip）**
- prebuilts 为 release 冻结；`extract-official-prebuilts.sh` 可用官方 OTA
  （OS3.0.305.0.WPLCNXM）重新校验/再生（不覆盖本地修改的 fstab/ueventd.rc）

## 触摸模块（dash）
- `nt38771_touch_dash.ko` + `xiaomi_touch_dash.ko`（Novatek 触摸）
- recovery init 通过 init.recovery.project.rc 的 dash-touch-bridge 服务加载

## 备注
- 若遇到 ninja "unknown option flag 'usesninjalogasweightlist'"：删 `out/.ninja_log` 或用兼容 ninja
- 若 recovery 卡第一屏：检查 cpio 打包必须用**相对路径**（`cd 目录 && find . | cpio -o`），不能用绝对路径
