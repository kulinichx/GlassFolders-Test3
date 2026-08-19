ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GlassFoldersPrefs
GlassFoldersPrefs_FILES = GFRootListController.m GFLivePreferencesNotifier.m
GlassFoldersPrefs_FRAMEWORKS = UIKit CoreFoundation
GlassFoldersPrefs_PRIVATE_FRAMEWORKS = Preferences
GlassFoldersPrefs_CFLAGS = -fobjc-arc
GlassFoldersPrefs_RESOURCE_FILES = Resources/GlassFolders.png Resources/GlassFolders@2x.png Resources/GlassFolders@3x.png Resources/GlassFoldersLarge.png
GlassFoldersPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
