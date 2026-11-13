THEOS ?= $(HOME)/theos
THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:17.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BadAppleSB

BadAppleSB_FILES = src/Tweak.x src/BadAppleController.m src/BadAppleCanvasView.m
BadAppleSB_CFLAGS = -fobjc-arc -Isrc
BadAppleSB_FRAMEWORKS = UIKit Foundation QuartzCore AVFoundation AudioToolbox
BadAppleSB_LIBRARIES = z

include $(THEOS_MAKE_PATH)/tweak.mk
