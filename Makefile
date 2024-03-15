CXX = g++
#CFLAGS=-Wall -O3 -g
CFLAGS=-Wall -O0 -g

%.o: %.cpp
	$(CXX) $(CFLAGS) -o $(notdir $@) -c $<

build: simon-test obj_simon_64_32_core/tb_simon_64_32_core obj_simon_128_64_core/tb_simon_128_64_core

simon-test: simon-test.o simon.o
	$(CXX) $(CFLAGS) -o simon-test $^

obj_simon_64_32_core/tb_simon_64_32_core:
	verilator --Mdir obj_simon_64_32_core -cc simon_core.sv -exe tb_simon_core.cpp simon.cpp -O0 \
	  -CFLAGS "-DSIMON_KEY_W=64 -DSIMON_DATA_W=32" \
	  -GSIMON_KEY_W=64 -GSIMON_DATA_W=32 -GSIMON_ROUNDS="7'd32" -GSIMON_ROUNDS_PER_CYCLE="7'd12"
	make OPT_FAST="-O0 -g" -C obj_simon_64_32_core -f Vsimon_core.mk Vsimon_core

obj_simon_128_64_core/tb_simon_128_64_core:
	verilator --Mdir obj_simon_128_64_core -cc simon_core.sv -exe tb_simon_core.cpp simon.cpp -O0 \
	  -CFLAGS "-DSIMON_KEY_W=128 -DSIMON_DATA_W=64" \
	  -GSIMON_KEY_W=128 -GSIMON_DATA_W=64 -GSIMON_ROUNDS="7'd44" -GSIMON_ROUNDS_PER_CYCLE="7'd12"
	make OPT_FAST="-O0 -g" -C obj_simon_128_64_core -f Vsimon_core.mk Vsimon_core

obj_simon_128_128/Vsimon_128_128_core:
	verilator --Mdir obj_simon_128_128 -cc simon_128_128_core.sv -exe tb_simon_128_128_core.cpp simon.cpp -O0
	make OPT_FAST="-O0 -g" -C obj_simon_128_128 -f Vsimon_128_128_core.mk Vsimon_128_128_core

clean:
	rm -rf *.o obj_simon_64_32_core obj_simon_128_64_core obj_simon_128_128_core simon-test
