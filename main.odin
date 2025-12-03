package os2test

import    "core:fmt"
import os "core:os/os2"

main :: proc() {
	fmt.println(os.args)

	fmt.println("running tests...")

	context.allocator = os.heap_allocator()

	file_basic_write()
	file_read_random()
	file_no_exist_err()
	file_double_close_err()
	file_permissions()
	file_times()
	file_size()
	file_links_and_names()
	paths()

	env_basic()
	process_env()
	process_script()
	process_pipes()
	process_info()
	process_errors()
	process_waits() // do last...

	fmt.println("tests pass !!")
}

assume_ok :: proc(err: os.Error, loc := #caller_location) {
	if err == nil {
		return
	}
	os.print_error(os.stderr, err, "unexpected error")
	panic("test failed", loc)
}


expect_error :: proc(err: os.Error, msg: string = "", loc := #caller_location) {
	s := "Expecting Error: "
	os.write(os.stdout, transmute([]u8)(s))
	assert(err != nil, "", loc)
	os.print_error(os.stderr, err, msg)
}

verify_contents :: proc(file: ^os.File, expected: string, loc := #caller_location) {
	// full read
	contents := make([]u8, len(expected) + 32)
	defer delete(contents)
	n, err := os.read(file, contents[:])
	assume_ok(err, loc)
	assert(string(contents[:n]) == expected, loc = loc)
}

create_write :: proc(name, contents: string, loc := #caller_location) -> (f: ^os.File) {
	err: os.Error
	f, err = os.open(name, {.Create, .Write, .Trunc}, os.Permissions_Read_Write_All)
	assume_ok(err, loc)

	n: int
	n, err = os.write(f, transmute([]u8)contents)
	assume_ok(err, loc)
	assert(n == len(contents), "", loc)

	assume_ok(os.flush(f), loc)  // really not necessary...
	return
}
