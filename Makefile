SHADER_DIR = Shaders
BUILD_DIR = .build
SHADER_BUILD_DIR = $(BUILD_DIR)/shaders
METAL_FILES = $(wildcard $(SHADER_DIR)/*.metal)
AIR_FILES = $(patsubst $(SHADER_DIR)/%.metal,$(SHADER_BUILD_DIR)/%.air,$(METAL_FILES))
INCLUDE_DIR = Sources/ShaderTypes/include

.PHONY: all build shaders run clean

all: build

shaders: $(BUILD_DIR)/default.metallib

$(SHADER_BUILD_DIR)/%.air: $(SHADER_DIR)/%.metal
	@mkdir -p $(SHADER_BUILD_DIR)
	xcrun metal -c -I $(INCLUDE_DIR) -o $@ $<

$(BUILD_DIR)/default.metallib: $(AIR_FILES)
	xcrun metallib -o $@ $^

build: shaders
	swift build
	@cp $(BUILD_DIR)/default.metallib $(BUILD_DIR)/debug/default.metallib 2>/dev/null || true

release: shaders
	swift build -c release
	@cp $(BUILD_DIR)/default.metallib $(BUILD_DIR)/release/default.metallib 2>/dev/null || true

run: build
	$(BUILD_DIR)/debug/MetalTest

clean:
	rm -rf $(SHADER_BUILD_DIR)
	rm -f $(BUILD_DIR)/default.metallib
	swift package clean
