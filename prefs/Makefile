ARCHS = arm64e
TARGET = iphone:clang:latest:16.0

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GlassFoldersPrefs

GlassFoldersPrefs_FILES = GFRootListController.m
GlassFoldersPrefs_FRAMEWORKS = UIKit CoreFoundation
GlassFoldersPrefs_PRIVATE_FRAMEWORKS = Preferences
GlassFoldersPrefs_CFLAGS = -fobjc-arc

GlassFoldersPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
