CXX = g++
#CFLAGS=-Wall -O3 -g
CFLAGS=-Wall -O0 -g

%.o: %.cpp
	$(CXX) $(CFLAGS) -o $(notdir $@) -c $<

build: simon-test obj_dir/Vsimon_128_64_core obj_dir/Vsimon_128_128_core

simon-test: simon-test.o simon.o
	$(CXX) $(CFLAGS) -o simon-test $^

obj_dir/Vsimon_128_64_core:
	verilator --Mdir obj_simon_128_64 -cc simon_128_64_core.sv -exe tb_simon_128_64_core.cpp simon.cpp -O0 -Wno-WIDTHTRUNC
	make OPT_FAST="-O3 -g" -C obj_simon_128_64 -f Vsimon_128_64_core.mk Vsimon_128_64_core

obj_dir/Vsimon_128_128_core:
	verilator --Mdir obj_simon_128_128 -cc simon_128_128_core.sv -exe tb_simon_128_128_core.cpp simon.cpp -O3
	make OPT_FAST="-O3 -g" -C obj_simon_128_128 -f Vsimon_128_128_core.mk Vsimon_128_128_core

clean:
	rm -rf *.o obj_dir obj_simon_128_64 obj_simon_128_128 simon-test
