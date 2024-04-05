package os2test

import "core:fmt"
import "core:os/os2"

main :: proc() {
	fmt.println("running tests...")

	context.allocator = os2.heap_allocator()

	file_basic_write()
	file_read_random()
	file_no_exist_err()
	file_double_close_err()
	file_symlinks()
	file_permissions()
	file_times()
	file_size()

	fmt.println("tests pass !!")
}

