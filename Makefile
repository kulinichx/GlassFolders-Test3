ARCHS = arm64e
TARGET = iphone:clang:latest:16.0

THEOS_PACKAGE_SCHEME = roothide
FINALPACKAGE = 1
DEBUG = 0

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GlassFoldersTest3
GlassFoldersTest3_FILES = Tweak.xm
GlassFoldersTest3_CFLAGS = -fobjc-arc
GlassFoldersTest3_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
