.DEFAULT_GOAL := help

PROJECT := fan.xcodeproj
SCHEME := fan
PRODUCT := fan
DERIVED_DATA := .build/DerivedData
DEBUG_BIN := $(DERIVED_DATA)/Build/Products/Debug/$(PRODUCT)
RELEASE_BIN := $(DERIVED_DATA)/Build/Products/Release/$(PRODUCT)
INSTALL_DIR := /usr/local/bin
INSTALL_BIN := $(INSTALL_DIR)/$(PRODUCT)
SUDO ?= sudo

.PHONY: help build release clean status auto max install uninstall

help:
	@printf "Available targets:\n"
	@printf "  make build      Build Debug binary and install to /usr/local/bin\n"
	@printf "  make release    Build Release binary\n"
	@printf "  make status     Build Debug and run 'fan status' with sudo\n"
	@printf "  make auto       Build Debug and run 'fan auto' with sudo\n"
	@printf "  make max        Build Debug and run 'fan max' with sudo\n"
	@printf "  make install    Build Release and install to /usr/local/bin\n"
	@printf "  make uninstall  Remove /usr/local/bin/fan\n"
	@printf "  make clean      Remove local build artifacts\n"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED_DATA) build
	$(SUDO) install -m 755 $(DEBUG_BIN) $(INSTALL_BIN)

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED_DATA) build

status: build
	$(SUDO) $(DEBUG_BIN) status

auto: build
	$(SUDO) $(DEBUG_BIN) auto

max: build
	$(SUDO) $(DEBUG_BIN) max

install: release
	$(SUDO) install -m 755 $(RELEASE_BIN) $(INSTALL_BIN)

uninstall:
	$(SUDO) rm -f $(INSTALL_BIN)

clean:
	rm -rf .build
