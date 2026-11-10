#
# LuCI 应用：eMMC 健康 / 寿命检测
#
# 页面读的是 /usr/bin/emmc-health（overlay 注入的脚本），显示
# Pre-EOL、寿命估计 A/B、累计写入量、CRC 错误计数等。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-emmc-health
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

LUCI_TITLE:=LuCI eMMC health / lifetime
LUCI_DESCRIPTION:=Show eMMC EXT_CSD health data (Pre-EOL, life time A/B, CRC errors)
LUCI_DEPENDS:=+mmc-utils
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
