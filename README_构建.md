# dash OrangeFox 14.1 构建指南

## 环境要求
- **OS**: Ubuntu 22.04 或更新（WSL2 也可）
- **内存**: 建议 16GB+（OrangeFox AOSP 构建较吃内存）
- **磁盘**: 至少 200GB 可用空间
- **工具链**: 
  - JDK 17（`sudo apt install openjdk-17-jdk`）
  - repo（`curl https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo && chmod +x ~/bin/repo`）
  - 基础依赖：`sudo apt install git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 libncurses-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig python3 bc cpio`

## 前置：同步 OrangeFox 14.1 源码树
本设备树依赖 OrangeFox 14.1（fox_14.1）AOSP 树，需包含 OrangeFox 框架 overlay：
- `bootable/recovery` = OrangeFox/bootable/Recovery（fox_14.1）
- `vendor/recovery` = OrangeFox/vendor/recovery（fox_14.1）
- `vendor/twrp/config/BoardConfigSoong.mk` 含 `include bootable/recovery/orangefox_soong.mk`
- build/make 已应用 OrangeFox sync 补丁（patch-manifest-fox_14.1.diff 等）

参考 dali 的 README：https://github.com/localhosts-A/device_xiaomi_dali_twrp

## 构建步骤
```bash
# 1. 解压设备树到 OrangeFox 树
tar xzf dash-OrangeFox14-device-tree.tar.gz -C /path/to/fox_14.1/device/xiaomi/
#    → device/xiaomi/dash

# 2. 一键构建（或手动）
cd /path/to/fox_14.1/device/xiaomi/dash
bash build.sh

# 手动步骤：
cd /path/to/fox_14.1
source build/envsetup.sh
lunch twrp_dash-ap2a-eng
m installclean
m vendorbootimage
# 然后按 build.sh 的第 3-5 步打包
```

## 分区/格式说明（dash）
- 刷入: `fastboot flash vendor_boot <img>`
- vendor_boot v4, 64MB
- cmdline: `bootopt=64S3,32N2,64N2`（无 erofs）
- 地址: ka 0x80000000 / ra 0xa6f00000 / tags 0x87c80000
- 双 gzip（platform + recovery），recovery 用 gzip 已在 dash 实测可进 REC

## prebuilt 说明
- `prebuilt/dtb/dash.dtb` = dash 官方 vendor_boot 的 DTB
- `prebuilt/recovery_modules/*.ko` = dash 恢复模式触摸模块
- `prebuilt/recovery_properties/*.prop` = dash 官方 build.prop
- `prebuilt/vendor_ramdisk/platform.cpio.gz` = **dash 官方完整 platform ramdisk（gzip）**——若缺，用 extract-official-prebuilts.sh 从官方 OTA 提取

## 触摸模块（dash）
- `nt38771_touch_dash.ko` + `xiaomi_touch_dash.ko`（Novatek 触摸）
- recovery init 通过 init.recovery.project.rc 的 dash-touch-bridge 服务加载

## 备注
- 若遇到 ninja "unknown option flag 'usesninjalogasweightlist'"：删 `out/.ninja_log` 或用兼容 ninja
- 若 recovery 卡第一屏：检查 cpio 打包必须用**相对路径**（`cd 目录 && find . | cpio -o`），不能用绝对路径
