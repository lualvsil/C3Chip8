SDK_VERSION=35

BUILD_DIR=build
APK_DIR=$(BUILD_DIR)/apk
RES_DIR=android/res
LIB_DIR=$(BUILD_DIR)/lib/arm64-v8a

# Android SDK / NDK
NDK_HOST=linux-aarch64

BUILD_TOOLS=$(shell ls -v "$(ANDROID_SDK_HOME)/build-tools" | tail -n1)

AAPT=$(ANDROID_SDK_HOME)/build-tools/$(BUILD_TOOLS)/aapt2
ZIP_ALIGN=$(ANDROID_SDK_HOME)/build-tools/$(BUILD_TOOLS)/zipalign
APK_SIGNER=$(ANDROID_SDK_HOME)/build-tools/$(BUILD_TOOLS)/apksigner
ANDROID_JAR=$(ANDROID_SDK_HOME)/platforms/android-$(SDK_VERSION)/android.jar

.PHONY: build/libc3chip8.so
build/libc3chip8.so:
	c3c build --target android-aarch64

apk: build/libc3chip8.so
	mkdir -p $(LIB_DIR)
	cp $(BUILD_DIR)/libc3chip8.so $(LIB_DIR)

	$(AAPT) compile -o $(BUILD_DIR)/res.zip --dir $(RES_DIR)

	cp $(ANDROID_NDK)/toolchains/llvm/prebuilt/$(NDK_HOST)/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so $(LIB_DIR)

	$(AAPT) link -o $(BUILD_DIR)/C3Chip8.apk \
		$(BUILD_DIR)/res.zip \
		--manifest android/AndroidManifest.xml \
		-I $(ANDROID_JAR)

	cd $(BUILD_DIR); zip -r C3Chip8.apk lib/

	$(ZIP_ALIGN) -p -f -v 4 $(BUILD_DIR)/C3Chip8.apk $(BUILD_DIR)/C3Chip8_aligned.apk

	$(APK_SIGNER) sign \
		--ks android/debug.jks \
		--ks-pass pass:123456 \
		--out $(BUILD_DIR)/C3Chip8_signed.apk \
		$(BUILD_DIR)/C3Chip8_aligned.apk

clean:
	rm -rf $(BUILD_DIR)