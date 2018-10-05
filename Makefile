compiler := nasm
compile_flags := -f elf64

linker := gcc
link_flags := -fno-pie -no-pie -m64

src_root := ./src/
main_file := $(src_root)/main.asm

obj_dir = ./obj/
obj_file = $(obj_dir)/http-asm.o
out_dir = ./bin/
out_file = $(out_dir)/http-asm

all:
	mkdir -p $(obj_dir) $(out_dir)
	$(compiler) $(compile_flags) $(main_file) -I$(src_root) -o $(obj_file)
	$(linker) $(link_flags) $(obj_file) -o $(out_file)
	rm -r $(obj_dir)


