CXX = g++
CFLAGS=-Wall -O3 -g

%.o: %.cpp
	$(CXX) $(CFLAGS) -o $(notdir $@) -c $<

build: simon-test obj_dir/Vsimon_128_128_core

simon-test: simon-test.o simon.o
	$(CXX) $(CFLAGS) -o simon-test $^

obj_dir/Vsimon_128_128_core:
	verilator -cc simon_128_128_core.sv -exe tb_simon_128_128_core.cpp simon.cpp -O3
	make OPT_FAST="-O3 -g" -C obj_dir -f Vsimon_128_128_core.mk Vsimon_128_128_core

clean:
	rm -rf *.o obj_dir simon-test
