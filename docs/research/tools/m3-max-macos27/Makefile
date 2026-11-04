SDK := $(shell xcrun --sdk macosx --show-sdk-path)
CC := $(shell xcrun --find clang)
CFLAGS := -O2 -fobjc-arc -Wall -Wextra -isysroot $(SDK)
LDLIBS := -framework Foundation -framework IOKit -lIOReport

.PHONY: all
all: power-sampler

power-sampler: power-sampler.m
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS)
