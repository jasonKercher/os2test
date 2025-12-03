package os2test

import    "core:time"
import os "core:os/os2"
import    "core:strings"

file_basic_write :: proc() {
	f := create_write("basic.txt", "hello os2")
	assume_ok(os.close(f))
	assume_ok(os.remove("basic.txt"))
}

file_read_random :: proc() {
	s := "01234567890abcdef"
	f := create_write("random.txt", s)
	assume_ok(os.close(f))

	err: os.Error
	f, err = os.open("random.txt")

	// full read
	n: int
	buf: [64]u8
	n, err = os.read(f, buf[:])
	assume_ok(err)
	assert(n == len(s))
	assert(string(buf[:n]) == s)

	// using read_at
	for i := 1; i < len(s); i += 1 {
		sub := s[i:]
		n, err = os.read_at(f, buf[:], i64(i))
		assume_ok(err)
		assert(n == len(sub))
		assert(string(buf[:n]) == sub)
	}

	// using seek
	for i := 1; i < len(s); i += 1 {
		sub := s[i:]
		os.seek(f, i64(i), .Start)
		n, err = os.read(f, buf[:])
		assume_ok(err)
		assert(n == len(sub))
		assert(string(buf[:n]) == sub)
	}
	assume_ok(os.close(f))
	assume_ok(os.remove("random.txt"))
}

file_no_exist_err :: proc() {
	f, err := os.open("file-that-does-not-exist.txt")
	assert(err != nil)
	assert(f == nil)
	expect_error(err, "file-that-does-not-exist.txt")
}

file_double_close_err :: proc() {
	f := create_write("double_close.txt", "close")
	assume_ok(os.close(f))
	assert(os.close(f) != nil)
	assume_ok(os.remove("double_close.txt"))
}

file_links_and_names :: proc() {
	if os.exists("new.txt") { assume_ok(os.remove("new.txt")) }
	// exists will currently not see a broken link
	if os.exists("link.txt") { assume_ok(os.remove("link.txt")) }
	if os.exists("target.txt") { assume_ok(os.remove("target.txt")) }

	s := "hello"
	f := create_write("target.txt", s)
	assume_ok(os.close(f))
	assume_ok(os.symlink("target.txt", "link.txt"))
	
	err: os.Error
	f, err = os.open("link.txt")

	buf: [64]u8
	n: int
	n, err = os.read(f, buf[:])
	assume_ok(err)
	assert(n == len(s))
	assert(string(buf[:n]) == s)
	assume_ok(os.close(f))

	link_name: string
	link_name, err = os.read_link("link.txt", context.allocator)
	assume_ok(err)
	assert(link_name == "target.txt")

	assume_ok(os.rename("target.txt", "new.txt"))
	link_name, err = os.read_link("link.txt", context.allocator)
	assume_ok(err)
	assert(link_name == "target.txt")

	f, err = os.open(link_name)
	expect_error(err, "(broken) link.txt")

	/* restore access via hard link and verify */
	assume_ok(os.link("new.txt", "target.txt"))
	f, err = os.open(link_name)
	assume_ok(err)
	verify_contents(f, s)

	assume_ok(os.remove("target.txt"))
	assume_ok(os.remove("link.txt")) // <<<<<<
	assume_ok(os.remove("new.txt"))
}

file_permissions :: proc() {
	f := create_write("perm.txt", "hello")

	assume_ok(os.close(f))
	assume_ok(os.chmod("perm.txt", os.Permissions_Read_All))

	err: os.Error
	f, err = os.open("perm.txt", {.Read, .Write})
	assert(err != nil)

	assume_ok(os.chmod("perm.txt", os.Permissions_Read_Write_All))
	f, err = os.open("perm.txt", {.Read, .Write})
	assume_ok(err)
	assume_ok(os.close(f))

	assume_ok(os.remove("perm.txt"))
}

file_times :: proc() {
	f0 := create_write("time0.txt", "hello")
	f1 := create_write("time1.txt", "hi")

	assume_ok(os.close(f0))
	// TODO: Something other than 0?
	assume_ok(os.chtimes("time0.txt", time.Time{0}, time.Time{0}))
	assume_ok(os.fchtimes(f1, time.Time{0}, time.Time{0}))

	info0, err0 := os.stat("time0.txt", context.allocator)
	assume_ok(err0)
	info1, err1 := os.fstat(f1, context.allocator)
	assume_ok(err1)
	assert(info0.type == .Regular && info1.type == .Regular)

	assert(info0.modification_time == info1.modification_time)
	assert(info0.access_time == info1.access_time)

	assume_ok(os.close(f1))
	assume_ok(os.remove("time0.txt"))
	assume_ok(os.remove("time1.txt"))
}

file_size :: proc() {
	blk: [512]u8
	f := create_write("file512.txt", string(blk[:]))
	s, err := os.file_size(f)
	assume_ok(err)
	assert(s == size_of(blk))

	assume_ok(os.sync(f))

	assume_ok(os.truncate(f, 128))
	s, err = os.file_size(f)
	assume_ok(err)
	assert(s == 128)

	assume_ok(os.remove("file512.txt"))
}

paths :: proc() {
	_make_dirs()
	_read_dirs()
	_change_dirs()
	_remove_dirs()
}

_make_dirs :: proc() {
	if os.exists("dir1") {
		assume_ok(os.remove_all("dir1"))
	}
	if os.exists("dir2-that-actually-has-a-pretty-long-name-and-stuff") {
		assume_ok(os.remove_all("dir2-that-actually-has-a-pretty-long-name-and-stuff"))
	}

	assume_ok(os.make_directory("dir1", 0o775))
	assume_ok(os.make_directory_all("dir2-that-actually-has-a-pretty-long-name-and-stuff/sub1/", 0o775))

	/* directories are writable... */
	f := create_write("dir1/test.txt", "hello")
	os.close(f)
	f = create_write("dir2-that-actually-has-a-pretty-long-name-and-stuff/sub1/test.txt", "hello")
	os.close(f)

	err := os.make_directory("dir-no-exist/sub1", 0o775)
	expect_error(err, "dir-no-exist")
}

_read_dirs :: proc() {
	found_dir1: bool
	found_dir2: bool

	f:   ^os.File
	err: os.Error
	f, err = os.open(".", {})
	assume_ok(err)

	fis: []os.File_Info
	fis, err = os.read_all_directory(f, context.allocator)
	assume_ok(err)

	for fi in fis {
		if fi.name == "dir1" {
			found_dir1 = true
		}
		if fi.name == "dir2-that-actually-has-a-pretty-long-name-and-stuff" {
			found_dir2 = true
		}
	}
	assert(found_dir1)
	assert(found_dir2)
}

_change_dirs :: proc() {
	base_dir, err := os.get_working_directory(context.allocator)
	assume_ok(err)
	defer delete(base_dir)

	/* access via relative path */
	assume_ok(os.set_working_directory("dir1"))

	dir1: string
	dir1, err = os.get_working_directory(context.allocator)
	assume_ok(err)
	defer delete(dir1)
	assert(dir1 != base_dir)

	/* access via full path */
	concat: [2]string = { base_dir, "/dir2-that-actually-has-a-pretty-long-name-and-stuff/sub1" }
	fullpath, mem_err := strings.concatenate(concat[:])
	assert(mem_err == nil)

	assume_ok(os.set_working_directory(fullpath))

	dir2: string
	dir2, err = os.get_working_directory(context.allocator)
	assume_ok(err)
	defer delete(dir2)
	assert(dir2 != base_dir)
	assert(dir2 != dir1)

	/* back to original directory if all went well. */
	assume_ok(os.set_working_directory("../../"))
	final_dir: string
	final_dir, err = os.get_working_directory(context.allocator)
	assume_ok(err)
	defer delete(final_dir)
	assert(final_dir == base_dir)
}

_remove_dirs :: proc() {
	assert(os.is_directory("dir1"))
	assert(os.is_directory("dir2-that-actually-has-a-pretty-long-name-and-stuff"))

	assume_ok(os.remove_all("dir1"))
	assume_ok(os.remove_all("dir2-that-actually-has-a-pretty-long-name-and-stuff"))

	assert(!os.is_directory("dir1"))
	assert(!os.is_directory("dir2-that-actually-has-a-pretty-long-name-and-stuff"))
}
