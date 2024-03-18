CXX = g++
CFLAGS=-Wall -O0 -g
VFLAGS=-Wall -O3

%.o: %.cpp
	$(CXX) $(CFLAGS) -o $(notdir $@) -c $<

build: simon-test obj_simon_64_32_core/Vsimon_core obj_simon_128_64_core/Vsimon_core obj_simon_128_128_core/Vsimon_core

test: build
	@echo "##"
	@echo "## Testing Simon cipher core: 64-bit key, 32-bit data"
	@echo "##"
	obj_simon_64_32_core/Vsimon_core --maxtrials 2000000
	@echo "##"
	@echo "## Testing Simon cipher core: 128-bit key, 64-bit data"
	@echo "##"
	obj_simon_128_64_core/Vsimon_core --maxtrials 2000000
	@echo "##"
	@echo "## Testing Simon cipher core: 128-bit key, 128-bit data"
	@echo "##"
	obj_simon_128_128_core/Vsimon_core --maxtrials 2000000

longtest: build
	@echo "##"
	@echo "## Testing Simon cipher core: 64-bit key, 32-bit data"
	@echo "##"
	obj_simon_64_32_core/Vsimon_core --maxtrials 20000000
	@echo "##"
	@echo "## Testing Simon cipher core: 128-bit key, 64-bit data"
	@echo "##"
	obj_simon_128_64_core/Vsimon_core --maxtrials 20000000
	@echo "##"
	@echo "## Testing Simon cipher core: 128-bit key, 128-bit data"
	@echo "##"
	obj_simon_128_128_core/Vsimon_core --maxtrials 20000000


simon-test: simon-test.o simon.o
	$(CXX) $(CFLAGS) -o simon-test $^

obj_simon_64_32_core/Vsimon_core:
	verilator $(VFLAGS) --Mdir obj_simon_64_32_core -cc simon_core.sv -exe tb_simon_core.cpp simon.cpp \
	  -CFLAGS "-DSIMON_KEY_W=64 -DSIMON_DATA_W=32" \
	  -GSIMON_KEY_W=64 -GSIMON_DATA_W=32 -GSIMON_ROUNDS="7'd32" -GSIMON_ROUNDS_PER_CYCLE="7'd12"
	make OPT_FAST="-O0 -g" -C obj_simon_64_32_core -f Vsimon_core.mk Vsimon_core

obj_simon_128_64_core/Vsimon_core:
	verilator $(VFLAGS) --Mdir obj_simon_128_64_core -cc simon_core.sv -exe tb_simon_core.cpp simon.cpp \
	  -CFLAGS "-DSIMON_KEY_W=128 -DSIMON_DATA_W=64" \
	  -GSIMON_KEY_W=128 -GSIMON_DATA_W=64 -GSIMON_ROUNDS="7'd44" -GSIMON_ROUNDS_PER_CYCLE="7'd12"
	make OPT_FAST="-O0 -g" -C obj_simon_128_64_core -f Vsimon_core.mk Vsimon_core

obj_simon_128_128_core/Vsimon_core:
	verilator $(VFLAGS) --Mdir obj_simon_128_128_core -cc simon_core.sv -exe tb_simon_core.cpp simon.cpp \
	  -CFLAGS "-DSIMON_KEY_W=128 -DSIMON_DATA_W=128" \
	  -GSIMON_KEY_W=128 -GSIMON_DATA_W=128 -GSIMON_ROUNDS="7'd68" -GSIMON_ROUNDS_PER_CYCLE="7'd12"
	make OPT_FAST="-O0 -g" -C obj_simon_128_128_core -f Vsimon_core.mk Vsimon_core

clean:
	rm -rf *.o obj_simon_64_32_core obj_simon_128_64_core obj_simon_128_128_core simon-test
