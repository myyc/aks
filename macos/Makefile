# Makefile for building macOS native libraries

CC = clang
CFLAGS = -shared -fPIC -O3 -Wall
LIBRAW_FLAGS = $(shell pkg-config --cflags --libs libraw || echo "-I/usr/local/include -L/usr/local/lib -lraw")

# Output directory
BUILD_DIR = .

# Targets
all: libraw_processor.dylib

libraw_processor.dylib: raw_processor/raw_processor.c
	$(CC) $(CFLAGS) -o $(BUILD_DIR)/libraw_processor.dylib \
		raw_processor/raw_processor.c \
		$(LIBRAW_FLAGS) -lm

clean:
	rm -f $(BUILD_DIR)/*.dylib

install: libraw_processor.dylib
	@echo "Library built successfully: $(BUILD_DIR)/libraw_processor.dylib"

.PHONY: all clean install