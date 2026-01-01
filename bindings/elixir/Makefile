MIX = mix
CFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter -fPIC

# Erlang paths
ERL_INCLUDE = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)

# Platform-specific settings
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS = -dynamiclib -undefined dynamic_lookup
	SO_EXT = .so
else
	LDFLAGS = -shared
	SO_EXT = .so
endif

# Paths
PRIV = priv
BUILD = $(MIX_BUILD_PATH)/lib/liquidz/priv
SRC = c_src
ZIG_LIB = ../../zig-out/lib

# Files
NIF_SRC = $(SRC)/liquidz_nif.c
NIF_SO = $(PRIV)/liquidz_nif$(SO_EXT)

all: $(PRIV) $(NIF_SO)

$(PRIV):
	mkdir -p $(PRIV)

$(NIF_SO): $(NIF_SRC)
	$(CC) $(CFLAGS) -I$(ERL_INCLUDE) $(NIF_SRC) \
		$(ZIG_LIB)/libliquidz_ffi.a \
		$(LDFLAGS) -o $(NIF_SO)

clean:
	rm -rf $(PRIV)

.PHONY: all clean
