ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0

THEOS_PACKAGE_SCHEME = roothide
FINALPACKAGE = 1
DEBUG = 0

INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GlassFolders
GlassFolders_FILES = Tweak.xm
GlassFolders_CFLAGS = -fobjc-arc
GlassFolders_FRAMEWORKS = UIKit CoreFoundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
