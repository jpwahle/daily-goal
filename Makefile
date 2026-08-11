APP_NAME = Daily Goal
EXEC_NAME = DailyGoal
VERSION ?= 1.0.0
DIST_DIR = dist
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME).app
EXECUTABLE = $(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)
DMG = $(DIST_DIR)/$(EXEC_NAME).dmg
# Set to your Developer ID for distribution, or leave empty for ad-hoc
SIGNING_IDENTITY ?=
# Set to your Apple ID for notarization
APPLE_ID ?=
TEAM_ID ?=

# Pin the sysroot explicitly. Without it, clang also scans /usr/local/include,
# which on some machines holds stray SDK header copies that break module builds.
export SDKROOT := $(shell xcrun --show-sdk-path)

.PHONY: release sign notarize dmg release-dmg run clean

# Release build (optimized, universal: arm64 + x86_64)
release:
	swift build -c release --arch arm64 --arch x86_64
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	@cp ".build/apple/Products/Release/$(EXEC_NAME)" "$(EXECUTABLE)"
	@lipo "$(EXECUTABLE)" -verify_arch arm64 x86_64 || \
		{ echo "❌ Expected universal binary, got: $$(lipo -archs "$(EXECUTABLE)")"; exit 1; }
	@echo "Architectures: $$(lipo -archs "$(EXECUTABLE)")"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	@printf 'APPL????' > "$(APP_BUNDLE)/Contents/PkgInfo"
	@if [ ! -f Resources/AppIcon.icns ]; then \
		echo "▸ Generating app icon…"; \
		rm -rf .build/AppIcon.iconset; \
		mkdir -p .build/AppIcon.iconset; \
		swift Scripts/MakeIcon.swift .build/AppIcon.iconset; \
		iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns; \
	fi
	@cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@echo "\n✅ Release built: $(APP_BUNDLE)"

# Code sign (for distribution outside App Store)
sign: release
	@if [ -z "$(SIGNING_IDENTITY)" ]; then \
		echo "⚠️  No SIGNING_IDENTITY set. Ad-hoc signing..."; \
		codesign --force --sign - "$(APP_BUNDLE)"; \
	else \
		echo "Signing with: $(SIGNING_IDENTITY)"; \
		codesign --force --options runtime --timestamp \
			--sign "$(SIGNING_IDENTITY)" "$(APP_BUNDLE)"; \
	fi
	@echo "✅ Signed: $(APP_BUNDLE)"

# Notarize (requires Apple Developer account)
notarize: sign
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(TEAM_ID)" ]; then \
		echo "❌ Set APPLE_ID and TEAM_ID for notarization"; \
		echo "   make notarize SIGNING_IDENTITY='Developer ID Application: ...' APPLE_ID=you@example.com TEAM_ID=ABC123"; \
		exit 1; \
	fi
	@echo "Creating ZIP for notarization..."
	@ditto -c -k --keepParent "$(APP_BUNDLE)" "$(DIST_DIR)/$(EXEC_NAME).zip"
	@if [ -n "$(KEYCHAIN_PROFILE)" ]; then \
		xcrun notarytool submit "$(DIST_DIR)/$(EXEC_NAME).zip" \
			--keychain-profile "$(KEYCHAIN_PROFILE)" --wait; \
	elif [ -n "$(APP_PASSWORD)" ]; then \
		xcrun notarytool submit "$(DIST_DIR)/$(EXEC_NAME).zip" \
			--apple-id "$(APPLE_ID)" --team-id "$(TEAM_ID)" \
			--password "$(APP_PASSWORD)" --wait; \
	else \
		echo "❌ Set KEYCHAIN_PROFILE (recommended) or APP_PASSWORD"; \
		echo "   Recommended: xcrun notarytool store-credentials AC_PASSWORD --apple-id ... --team-id ... --password ..."; \
		echo "   Then: make notarize SIGNING_IDENTITY='...' APPLE_ID=... TEAM_ID=... KEYCHAIN_PROFILE=AC_PASSWORD"; \
		exit 1; \
	fi
	xcrun stapler staple "$(APP_BUNDLE)"
	@rm -f "$(DIST_DIR)/$(EXEC_NAME).zip"
	@echo "✅ Notarized and stapled: $(APP_BUNDLE)"

# Create DMG for distribution (styled with drag-to-Applications layout)
dmg: sign
	@rm -f "$(DMG)"
	./Scripts/create-dmg.sh "$(APP_NAME)" "$(APP_BUNDLE)" "$(DMG)"
	@echo "✅ DMG created: $(DMG)"

# Full distribution build: sign → notarize → staple → DMG → sign DMG → notarize DMG
release-dmg: notarize
	@rm -f "$(DMG)"
	./Scripts/create-dmg.sh "$(APP_NAME)" "$(APP_BUNDLE)" "$(DMG)"
	codesign --force --sign "$(SIGNING_IDENTITY)" "$(DMG)"
	@if [ -n "$(KEYCHAIN_PROFILE)" ]; then \
		xcrun notarytool submit "$(DMG)" \
			--keychain-profile "$(KEYCHAIN_PROFILE)" --wait; \
	else \
		xcrun notarytool submit "$(DMG)" \
			--apple-id "$(APPLE_ID)" --team-id "$(TEAM_ID)" \
			--password "$(APP_PASSWORD)" --wait; \
	fi
	xcrun stapler staple "$(DMG)"
	@echo "✅ Distribution-ready DMG: $(DMG)"

# Build and run
run: release
	@open "$(APP_BUNDLE)"

# Clean build artifacts
clean:
	rm -rf .build $(DIST_DIR)
	@echo "✅ Cleaned"
