SHELL := /bin/bash
.DEFAULT_GOAL := help

CONFIGURATION ?= Debug
DERIVED_DATA ?= $(CURDIR)/build/DerivedData
RACKET_BUNDLE_PREFIX ?= io.github.iamcaglardogan
XCODEGEN := $(CURDIR)/.tools/xcodegen-2.46.0/xcodegen/bin/xcodegen
XCODEBUILD := xcrun xcodebuild
XCODE_FLAGS := -project RACKET.xcodeproj -scheme RACKET -configuration $(CONFIGURATION) -derivedDataPath "$(DERIVED_DATA)" RACKET_BUNDLE_PREFIX="$(RACKET_BUNDLE_PREFIX)" CODE_SIGNING_ALLOWED=NO

.PHONY: help bootstrap project check-xcode build test core-build core-test release

help:
	@printf '%s\n' \
	  'make bootstrap  Download the pinned XcodeGen build tool into .tools' \
	  'make project    Generate the untracked Xcode project' \
	  'make build      Build the unsigned macOS app for Apple Silicon and Intel' \
	  'make test       Run the Xcode test target (empty in Phase 0)' \
	  'make core-build Build the headless core with Swift 6 Command Line Tools' \
	  'make core-test  Run the headless Swift package tests (XCTest required)' \
	  'make release    Reserved for signed distribution in Phase 9'

bootstrap:
	@bash scripts/bootstrap-xcodegen.sh

project: bootstrap
	@"$(XCODEGEN)" generate --spec project.yml

check-xcode:
	@bash scripts/check-xcode.sh

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

release:
	@printf '%s\n' 'Signed and notarized releases are implemented in Phase 9. No release artifact was produced.' >&2
	@exit 1
