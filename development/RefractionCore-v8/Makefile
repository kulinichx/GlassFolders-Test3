# Standalone Theos compile target. NOT injected into SpringBoard/backboardd.
# No RootHide module is assumed: only set THEOS_PACKAGE_SCHEME if installed.
TARGET = iphone:clang:latest:16.0
ARCHS ?= arm64 arm64e
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = GFRefractionCore
GFRefractionCore_FILES = src/GFRefractionRenderer.mm src/GFBackboardLiveFrameBridge.mm
GFRefractionCore_FRAMEWORKS = Foundation Metal CoreGraphics
GFRefractionCore_CFLAGS = -fobjc-arc -std=c++17 -Wall -Wextra

include $(THEOS_MAKE_PATH)/library.mk
