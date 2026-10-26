ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
FINALPACKAGE = 1
INSTALL_TARGET_PROCESSES =
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = GFOpticsProbe
GFOpticsProbe_FILES = main.mm GFProbeViewController.mm ../GFStandaloneRefractionRenderer.mm
GFOpticsProbe_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/..
GFOpticsProbe_FRAMEWORKS = UIKit Foundation Metal MetalKit QuartzCore
GFOpticsProbe_RESOURCE_FILES = Resources/GFOpticsLab05.metallib
include $(THEOS_MAKE_PATH)/application.mk
