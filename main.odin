package os2test

import "core:fmt"
import "core:time"
import "core:os/os2"

main :: proc() {
	time.sleep(15 * time.Second)

	fmt.println(os2.args)

	fmt.println("running tests...")

	context.allocator = os2.heap_allocator()

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
	process_signals()
	process_waits() // do last...

	fmt.println("tests pass !!")
}

assume_ok :: proc(err: os2.Error, loc := #caller_location) {
	if err == nil {
		return
	}
	os2.print_error(err, "unexpected error")
	panic("test failed", loc)
}


expect_error :: proc(err: os2.Error, msg: string = "", loc := #caller_location) {
	s := "Expecting Error: "
	os2.write(os2.stdout, transmute([]u8)(s))
	assert(err != nil, "", loc)
	os2.print_error(err, msg)
}

verify_contents :: proc(file: ^os2.File, expected: string, loc := #caller_location) {
	// full read
	contents := make([]u8, len(expected) + 32)
	defer delete(contents)
	n, err := os2.read(file, contents[:])
	assume_ok(err, loc)
	assert(string(contents[:n]) == expected, loc = loc)
}

create_write :: proc(name, contents: string, loc := #caller_location) -> (f: ^os2.File) {
	err: os2.Error
	f, err = os2.open(name, {.Create, .Write, .Trunc}, 0o664)
	assume_ok(err, loc)

	n: int
	n, err = os2.write(f, transmute([]u8)contents)
	assume_ok(err, loc)
	assert(n == len(contents), "", loc)

	assume_ok(os2.flush(f), loc)  // really not necessary...
	return
}
