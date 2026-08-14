ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GlassFoldersPrefs

GlassFoldersPrefs_FILES = GFRootListController.m
GlassFoldersPrefs_FRAMEWORKS = UIKit CoreFoundation
GlassFoldersPrefs_PRIVATE_FRAMEWORKS = Preferences
GlassFoldersPrefs_CFLAGS = -fobjc-arc
GlassFoldersPrefs_RESOURCE_FILES = Resources/GlassFoldersIcon.png Resources/GlassFoldersIcon@2x.png Resources/GlassFoldersIcon@3x.png Resources/GlassFoldersIconLarge.png

GlassFoldersPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
