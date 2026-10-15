BUILD_DIR := build
BINARY := $(BUILD_DIR)/ntfsremount
SOURCE := Sources/ntfsremount/main.swift
LABEL := com.i5dr0id.ntfsremount

.PHONY: build clean install uninstall logs status

build: $(BINARY)

$(BINARY): $(SOURCE)
	@mkdir -p $(BUILD_DIR)
	swiftc -O -o $(BINARY) $(SOURCE)

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
