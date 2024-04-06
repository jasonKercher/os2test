package os2test

import "core:time"
import "core:os/os2"

file_basic_write :: proc() {
	f := _create_write("basic.txt", "hello os2")
	assume_ok(os2.close(f))
	assume_ok(os2.remove("basic.txt"))
}

file_read_random :: proc() {
	s := "01234567890abcdef"
	f := _create_write("random.txt", s)
	assume_ok(os2.close(f))

	err: os2.Error
	f, err = os2.open("random.txt")

	// full read
	n: int
	buf: [64]u8
	n, err = os2.read(f, buf[:])
	assume_ok(err)
	assert(n == len(s))
	assert(string(buf[:n]) == s)

	// using read_at
	for i := 1; i < len(s); i += 1 {
		sub := s[i:]
		n, err := os2.read_at(f, buf[:], i64(i))
		assume_ok(err)
		assert(n == len(sub))
		assert(string(buf[:n]) == sub)
	}

	// using seek
	for i := 1; i < len(s); i += 1 {
		sub := s[i:]
		os2.seek(f, i64(i), .Start)
		n, err := os2.read(f, buf[:])
		assume_ok(err)
		assert(n == len(sub))
		assert(string(buf[:n]) == sub)
	}
	assume_ok(os2.close(f))
	assume_ok(os2.remove("random.txt"))
}

file_no_exist_err :: proc() {
	f, err := os2.open("file-that-does-not-exist.txt")
	assert(err != nil)
	assert(f == nil)
	expect_error(err, "file-that-does-not-exist.txt")
}

file_double_close_err :: proc() {
	f := _create_write("double_close.txt", "close")
	assume_ok(os2.close(f))
	assert(os2.close(f) != nil)
	assume_ok(os2.remove("double_close.txt"))
}

file_links_and_names :: proc() {
	if os2.exists("new.txt") { assume_ok(os2.remove("new.txt")) }
	if os2.exists("link.txt") { assume_ok(os2.remove("link.txt")) }
	if os2.exists("target.txt") { assume_ok(os2.remove("target.txt")) }

	s := "hello"
	f := _create_write("target.txt", s)
	assume_ok(os2.close(f))
	assume_ok(os2.symlink("target.txt", "link.txt"))
	
	err: os2.Error
	f, err = os2.open("link.txt")

	buf: [64]u8
	n: int
	n, err = os2.read(f, buf[:])
	assume_ok(err)
	assert(n == len(s))
	assert(string(buf[:n]) == s)
	assume_ok(os2.close(f))

	link_name: string
	link_name, err = os2.read_link("link.txt", context.allocator)
	assume_ok(err)
	assert(link_name == "target.txt")

	assume_ok(os2.rename("target.txt", "new.txt"))
	link_name, err = os2.read_link("link.txt", context.allocator)
	assume_ok(err)
	assert(link_name == "target.txt")

	f, err = os2.open(link_name)
	expect_error(err, "(broken) link.txt")

	/* restore access via hard link and verify */
	assume_ok(os2.link("new.txt", "target.txt"))
	f, err = os2.open(link_name)
	assume_ok(err)
	verify_contents(f, s)

	assume_ok(os2.remove("target.txt"))
	assume_ok(os2.remove("link.txt"))
	assume_ok(os2.remove("new.txt"))
}

file_permissions :: proc() {
	f := _create_write("perm.txt", "hello")

	assume_ok(os2.close(f))
	assume_ok(os2.chmod("perm.txt", 0o444)) // read only

	err: os2.Error
	f, err = os2.open("perm.txt", {.Read, .Write})
	assert(err != nil)

	assume_ok(os2.chmod("perm.txt", 0o666)) // read-write
	f, err = os2.open("perm.txt", {.Read, .Write})
	assume_ok(err)
	assume_ok(os2.close(f))

	assume_ok(os2.remove("perm.txt"))
}

file_times :: proc() {
	f0 := _create_write("time0.txt", "hello")
	f1 := _create_write("time1.txt", "hi")

	assume_ok(os2.close(f0))
	assume_ok(os2.chtimes("time0.txt", time.Time{0}, time.Time{0}))
	assume_ok(os2.fchtimes(f1, time.Time{0}, time.Time{0}))

	info0, err0 := os2.stat("time0.txt", context.allocator)
	assume_ok(err0)
	info1, err1 := os2.fstat(f1, context.allocator)
	assume_ok(err1)

	assert(info0.modification_time == info1.modification_time)
	assert(info0.access_time == info1.access_time)

	assume_ok(os2.close(f1))
	assume_ok(os2.remove("time0.txt"))
	assume_ok(os2.remove("time1.txt"))
}

file_size :: proc() {
	blk: [512]u8
	f := _create_write("file512.txt", string(blk[:]))
	s, err := os2.file_size(f)
	assume_ok(err)
	assert(s == size_of(blk))

	assume_ok(os2.sync(f))

	assume_ok(os2.truncate(f, 128))
	s, err = os2.file_size(f)
	assume_ok(err)
	assert(s == 128)

	assume_ok(os2.remove("file512.txt"))
}

_create_write :: proc(name, contents: string) -> (f: ^os2.File) {
	err: os2.Error
	f, err = os2.create(name)
	assume_ok(err)

	n: int
	n, err = os2.write(f, transmute([]u8)contents)
	assume_ok(err)
	assert(n == len(contents))

	assume_ok(os2.flush(f))  // really not necessary...
	return
}
