TARGET_NAME = eth_dpi

all: clean $(TARGET_NAME)

CC = g++ -xc
CPP= g++ -xc++
LD = g++
OBJDUMP = objdump 
DEFAULT_CP := cp -f
DEFAULT_MKDIR := mkdir -p
DEFAULT_RM := rm -rf

MSIM_INCLUDES := $(shell echo $$MSIM_INCLUDES)

INCDIR := ./ \
 $(MSIM_INCLUDES)

INCLUDE := $(addprefix -I, $(INCDIR))
CFLAGS := -DMSIM 
CFLAGS += -D_64BIT
CFLAGS += -g
CFLAGS += $(INCLUDE)
CFLAGS += $(shell echo $$MSIM_GNU_FLAGS)

LDFLAGS := $(shell echo $$MSIM_GNU_FLAGS)
LDFLAGS += -Wl,-Map=$(TARGET_NAME).map

C_SRCS := $(wildcard *.c)
C_SRCS += $(wildcard ./pcap/*.c)
C_SRCS += $(wildcard ./ether/*.c)

OBJFILE_C := $(patsubst %.c,%.o, $(C_SRCS))

$(TARGET_NAME): $(OBJFILE_C)
	echo $(MSIM_INCLUDES)
	@echo C_SRCS: $(C_SRCS)
	$(LD) -shared -o $(TARGET_NAME).so $(notdir $^) $(LDFLAGS) $(LIBRARIES)
	$(OBJDUMP) -S -d $(TARGET_NAME).so > $(TARGET_NAME).objdump
	rm -f *.o
	rm -f *.d
	@echo DPI-C so-lib built successfully.

%.o: %.c
	@echo Compiling $<:
	$(CC) $(CFLAGS) $(LIBRARIES) -fPIC -c $<

clean:
	@echo "Cleaning build artifacts..."
	$(DEFAULT_RM) *.o 
	$(DEFAULT_RM) *.d
	$(DEFAULT_RM) *.objdump
	$(DEFAULT_RM) *.map
	$(DEFAULT_RM) $(TARGET_NAME).so
	@echo "Clean complete."
