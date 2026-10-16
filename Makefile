SHELL := /bin/bash
.DEFAULT_GOAL := help

CONFIGURATION ?= Debug
DERIVED_DATA ?= $(CURDIR)/build/DerivedData
RACKET_BUNDLE_PREFIX ?= io.github.iamcaglardogan
XCODEGEN := $(CURDIR)/.tools/xcodegen-2.46.0/xcodegen/bin/xcodegen
XCODEBUILD := xcrun xcodebuild
XCODE_FLAGS := -project RACKET.xcodeproj -scheme RACKET -configuration $(CONFIGURATION) -derivedDataPath "$(DERIVED_DATA)" RACKET_BUNDLE_PREFIX="$(RACKET_BUNDLE_PREFIX)" CODE_SIGNING_ALLOWED=NO
APP_PATH ?= $(DERIVED_DATA)/Build/Products/Release/RACKET.app
OUTPUT_DIR ?=

.PHONY: help bootstrap project check-xcode check-policy build test core-build core-test package release

help:
	@printf '%s\n' \
	  'make bootstrap  Download the pinned XcodeGen build tool into .tools' \
	  'make project    Generate the untracked Xcode project' \
	  'make build      Build the unsigned macOS app for Apple Silicon and Intel' \
	  'make test       Run the Xcode safety test target' \
	  'make core-build Build the headless core with Swift 6 Command Line Tools' \
	  'make core-test  Run the headless Swift package tests (XCTest required)' \
	  'make check-policy Check source safety boundaries' \
	  'make package    Verify and create local ad-hoc signed ZIP/DMG archives' \
	  'make release    Require Developer ID credentials, sign and notarize archives'

bootstrap:
	@bash scripts/bootstrap-xcodegen.sh

project: bootstrap
	@"$(XCODEGEN)" generate --spec project.yml

check-xcode:
	@bash scripts/check-xcode.sh

check-policy:
	python3 scripts/test-source-policy.py
	python3 scripts/check-source-policy.py

build: check-xcode project
	$(XCODEBUILD) $(XCODE_FLAGS) -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build

test: check-xcode project
	$(XCODEBUILD) $(XCODE_FLAGS) -destination 'platform=macOS' test

core-build:
	@mkdir -p "$(CURDIR)/.cache/clang" "$(CURDIR)/.cache/swiftpm"
	CLANG_MODULE_CACHE_PATH="$(CURDIR)/.cache/clang" swift build --scratch-path "$(CURDIR)/.build" --cache-path "$(CURDIR)/.cache/swiftpm"

core-test:
	@mkdir -p "$(CURDIR)/.cache/clang" "$(CURDIR)/.cache/swiftpm"
	CLANG_MODULE_CACHE_PATH="$(CURDIR)/.cache/clang" swift test --scratch-path "$(CURDIR)/.build" --cache-path "$(CURDIR)/.cache/swiftpm"

package:
	@bash scripts/package-app.sh "$(APP_PATH)" $(if $(OUTPUT_DIR),"$(OUTPUT_DIR)")

release:
	@bash scripts/release-app.sh "$(APP_PATH)" $(if $(OUTPUT_DIR),"$(OUTPUT_DIR)")
