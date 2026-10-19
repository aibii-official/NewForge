# NewForge - zero-dependency build (no XcodeGen / no full Xcode required)
#
#   make            build everything into build/
#   make run        build, then open NewForge.app (activates the extension)
#   make test       compile & run the NewForgeKit unit tests
#   make install    copy NewForge.app to /Applications (asks for approval)
#   make clean

BUILD       := build
MODULECACHE := $(abspath $(BUILD))/ModuleCache
APP         := $(BUILD)/NewForge.app
APPEXE      := $(APP)/Contents/MacOS/NewForge
EXT         := $(APP)/Contents/PlugIns/NewForgeFinderExt.appex
EXTEXE      := $(EXT)/Contents/MacOS/NewForgeFinderExt
KIT         := $(BUILD)/libNewForgeKit.a
APPSWIFTS   := $(wildcard Sources/NewForgeApp/*.swift)
KITSWIFTS   := $(wildcard Sources/NewForgeKit/*.swift)
EXTSWIFTS   := $(wildcard Sources/NewForgeFinderExt/*.swift)
TESTSWIFTS  := $(wildcard Tests/NewForgeKitTests/*.swift)

SDK         := $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)
TARGET      := arm64-apple-macosx14.0
SWIFTC      := xcrun swiftc
PLUGINKIT   := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

BUNDLE_ID   := com.newforge.app
EXT_BUNDLE_ID := com.newforge.app.finderext

.PHONY: all run test install clean

all: $(APP)

# ---------- NewForgeKit (static library, arm64) ----------
$(KIT): $(KITSWIFTS)
	@mkdir -p $(BUILD)/kit-obj
	cd $(BUILD)/kit-obj && \
	$(SWIFTC) -emit-object \
	  -module-name NewForgeKit \
	  -sdk "$(SDK)" -target $(TARGET) \
	  -module-cache-path "$(MODULECACHE)" \
	  -emit-module -emit-module-path "$(abspath $(BUILD))/NewForgeKit.swiftmodule" \
	  -parse-as-library \
	  -enable-testing \
	  $(abspath $(KITSWIFTS))
	ar rcs $@ $(BUILD)/kit-obj/*.o

# ---------- Finder extension ----------
$(EXTEXE): $(KIT) $(EXTSWIFTS) NewForgeFinderExt/Info.plist
	@mkdir -p $(EXT)/Contents/MacOS $(EXT)/Contents/Resources
	$(SWIFTC) -emit-executable \
	  -module-name NewForgeFinderExt \
	  -sdk $(SDK) -target $(TARGET) \
	  -module-cache-path "$(MODULECACHE)" \
	  -I $(BUILD) $(EXTSWIFTS) \
	  -L $(BUILD) -lNewForgeKit \
	  -framework Cocoa -framework FinderSync -framework Foundation \
	  -Xlinker -e -Xlinker _NSExtensionMain \
	  -o $(EXTEXE)
	cp NewForgeFinderExt/Info.plist $(EXT)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(EXT_BUNDLE_ID)" $(EXT)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable NewForgeFinderExt" $(EXT)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType XPC!" $(EXT)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleName NewForgeFinderExt" $(EXT)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" $(EXT)/Contents/Info.plist
	# Templates ship inside the appex: the sandboxed extension cannot read
	# them from the host app's Resources.
	cp -R Resources/Templates $(EXT)/Contents/Resources/Templates
	cp -R Resources/en.lproj $(EXT)/Contents/Resources/ 2>/dev/null || true
	cp -R Resources/zh-Hans.lproj $(EXT)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign - $(EXT) 2>/dev/null || true

# ---------- Container app ----------
$(APPEXE): $(KIT) $(APPSWIFTS) NewForge/NewForge-Info.plist
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	$(SWIFTC) \
	  -module-name NewForge \
	  -sdk $(SDK) -target $(TARGET) \
	  -module-cache-path "$(MODULECACHE)" \
	  -I $(BUILD) $(APPSWIFTS) \
	  -L $(BUILD) -lNewForgeKit \
	  -framework Cocoa -framework SwiftUI \
	  -o $(APPEXE)
	cp NewForge/NewForge-Info.plist $(APP)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_ID)" $(APP)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable NewForge" $(APP)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" $(APP)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleName NewForge" $(APP)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" $(APP)/Contents/Info.plist

$(APP): $(APPEXE) $(EXTEXE)
	@mkdir -p $(APP)/Contents/PlugIns
	cp -R Resources/Templates $(APP)/Contents/Resources/Templates
	cp -R Resources/en.lproj $(APP)/Contents/Resources/ 2>/dev/null || true
	cp -R Resources/zh-Hans.lproj $(APP)/Contents/Resources/ 2>/dev/null || true
	cp -R Resources/Assets.xcassets $(APP)/Contents/Resources/ 2>/dev/null || true
	codesign --force --deep --sign - $(APP) 2>/dev/null || true
	$(PLUGINKIT) -f -R trusted $(APP) 2>/dev/null || true
	@echo ""
	@echo "Built $(APP)"
	@echo "Run 'make run' to launch it, then enable the extension in"
	@echo "System Settings > Privacy & Security > Extensions > Finder."

run: $(APP)
	open $(APP)

# ---------- tests ----------
test: $(KIT) $(TESTSWIFTS)
	@mkdir -p $(BUILD)/tests
	$(SWIFTC) \
	  -module-name NewForgeKitTests \
	  -sdk $(SDK) -target $(TARGET) \
	  -module-cache-path "$(MODULECACHE)" \
	  -I $(BUILD) $(TESTSWIFTS) \
	  -L $(BUILD) -lNewForgeKit \
	  -enable-testing \
	  -framework Cocoa \
	  -o $(BUILD)/tests/runner
	$(BUILD)/tests/runner

# Install the Xcode-built product (which has proper signing and a
# provisioning profile) rather than the ad-hoc Makefile build, so the
# extension actually loads.
install:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
	  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
	  -project NewForge.xcodeproj -scheme NewForge -configuration Release \
	  -derivedDataPath build/DerivedData -allowProvisioningUpdates build
	$(eval RELEASE_APP := build/DerivedData/Build/Products/Release/NewForge.app)
	# Stop any running copy, replace /Applications, re-register, restart.
	-killall NewForge 2>/dev/null
	-killall Finder 2>/dev/null
	rm -rf /Applications/NewForge.app
	cp -R $(RELEASE_APP) /Applications/NewForge.app
	$(PLUGINKIT) -f -R trusted /Applications/NewForge.app 2>/dev/null || true
	open /Applications/NewForge.app
	@echo ""
	@echo "Installed to /Applications/NewForge.app and launched."
	@echo "The app registers itself as a login item on first launch."

clean:
	rm -rf $(BUILD)
