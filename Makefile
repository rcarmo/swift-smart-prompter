SHELL := /bin/bash
.DEFAULT_GOAL := build

APP_NAME := Smart Prompter
PRODUCT_NAME := SmartPrompter
BUNDLE_ID ?= com.taoofmac.stageprompter
CONFIGURATION ?= debug
APP := build/$(APP_NAME).app

.PHONY: build package-build run test clean

package-build:
	swift build --disable-sandbox --product $(PRODUCT_NAME) --configuration $(CONFIGURATION)

test:
	swift test --disable-sandbox

build: package-build
	./scripts/build-macos-app.sh "$(CONFIGURATION)" "$(BUNDLE_ID)"

run: build
	open "$(APP)"

clean:
	rm -rf .build build
