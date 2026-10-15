BUILD_DIR := build
APP := $(BUILD_DIR)/NTFSRemount.app
BINARY := $(APP)/Contents/MacOS/ntfsremount
SOURCE := Sources/ntfsremount/main.swift
APP_INFO := Resources/App-Info.plist
BUNDLE_ID := com.i5dr0id.ntfsremount
LABEL := com.i5dr0id.ntfsremount

.PHONY: build clean install uninstall logs status

build: $(BINARY) $(APP)/Contents/Info.plist
	@codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP)" >/dev/null 2>&1 || \
		echo "warning: codesign failed"
	@echo "built $(APP)"

$(BINARY): $(SOURCE)
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	swiftc -O -o "$(BINARY)" $(SOURCE)

$(APP)/Contents/Info.plist: $(APP_INFO)
	@mkdir -p "$(APP)/Contents"
	cp "$(APP_INFO)" "$@"

clean:
	rm -rf $(BUILD_DIR)

install: build
	sudo scripts/install.sh

uninstall:
	sudo scripts/uninstall.sh

logs:
	tail -f /var/log/ntfsremount.log

status:
	launchctl print system/$(LABEL) 2>/dev/null || echo "not loaded"
