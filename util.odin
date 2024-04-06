package os2test

import "core:os/os2"

assume_ok :: proc(err: os2.Error, loc := #caller_location) {
	if err == nil {
		return
	}
	os2.print_error(err, "unexpected error")
	panic("test failed", loc)
}


expect_error :: proc(err: os2.Error, msg: string = "", loc := #caller_location) {
	assert(err != nil, "", loc)
	s := "EXECTED ERROR: "
	os2.write(os2.stdout, transmute([]u8)(s))
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
