package os2test

import "core:fmt"
import "core:time"
import "core:os/os2"

import "base:runtime"
import "core:sync"
import "core:sys/linux"

_gen_odin: [64]u8

_run_background :: proc(program: string, desc: ^os2.Process_Desc = nil, loc := #caller_location) -> (os2.Process, os2.Error) {
	@static i := 0
	fmt.bprintf(_gen_odin[:], "generated%d.odin", i)
	i += 1

	f := create_write(string(_gen_odin[:]), program)
	assume_ok(os2.close(f), loc)

	/* Build our program */
	{
		args := [?]string {"./odin", "build", string(_gen_odin[:]), "-file", "-out:generated"}
		odin_build_desc: os2.Process_Desc
		odin_build_desc.command = args[:]

		odin_build, odin_err := os2.process_start(odin_build_desc)
		assume_ok(odin_err, loc)
		if _reap(&odin_build) != 0 {
			fmt.println("Failed to build program at", loc)
			os2.exit(2)
		}
	}

	/* Run our program */
	{
		args := [?]string { "./generated" }

		new_desc: os2.Process_Desc
		if desc != nil {
			new_desc = desc^
		}

		if new_desc.command == nil {
			new_desc.command = args[:]
		}
		p, err := os2.process_start(new_desc)
		return p, err
	}
}

_reap :: proc(process: ^os2.Process, loc := #caller_location) -> int {
	state, err := os2.process_wait(process^)
	assume_ok(err, loc)
	assert(state.exited, "", loc)
	//assume_ok(os2.remove(string(_gen_odin[:])), loc)
	return state.exit_code
}

_run :: proc(program: string, desc: ^os2.Process_Desc= nil, loc := #caller_location) -> int {
	p, err := _run_background(program, desc, loc)
	assume_ok(err, loc)
	return _reap(&p, loc)
}

env_basic :: proc() {
	val, found := os2.lookup_env("DoEs-NoT-ExIsT", context.allocator)
	assert(!found)

	path: string
	path, found = os2.lookup_env("PATH", context.allocator)
	assert(found)
	assert(len(path) != 0)

	env := os2.environ(context.allocator)
	env_size := len(env)
	delete(env)

	os2.set_env("os2_env_KEY", "VALUE")
	val, found = os2.lookup_env("os2_env_KEY", context.allocator)
	assert(found)
	assert(val == "VALUE")

	env = os2.environ(context.allocator)
	assert(len(env) == env_size + 1)
	delete(env)

	assert(os2.unset_env("os2_env_KEY"))
	assert(!os2.unset_env("os2_env_KEY"))

	env = os2.environ(context.allocator)
	defer delete(env)
	assert(len(env) == env_size)
}

process_env :: proc() {
	program := `
	package auto
	import "core:os/os2"
	main :: proc() {
		res := 0
		env := os2.environ(context.allocator)
		if len(env) <= 0 { os2.exit(1) }
		os2.clear_env()
		env = os2.environ(context.allocator)
		if len(env) != 0 { os2.exit(2) }
	}
	`
	assert(_run(program) == 0)

	org_env := os2.environ(context.allocator)
	os2.set_env("var_to_read_in_child", "child")
	/* should inherit our new var */
	program = `
	package auto
	import "core:os/os2"
	main :: proc() {
		val, found := os2.lookup_env("var_to_read_in_child", context.allocator)
		if !found { os2.exit(1) }
		if val != "child" { os2.exit(2) }assert(found && val == "child")
	}
	`
	assert(_run(program) == 0)

	desc: os2.Process_Desc = {
		env = org_env,
	}

	assert(_run(program, &desc) != 0)
}


process_pipes :: proc() {
	READ  :: 0
	WRITE :: 1

	stdin_pipe:  [2]^os2.File
	stdout_pipe: [2]^os2.File
	stderr_pipe: [2]^os2.File

	err: os2.Error

	stdin_pipe[READ], stdin_pipe[WRITE], err = os2.pipe()
	assume_ok(err)
	stdout_pipe[READ], stdout_pipe[WRITE], err = os2.pipe()
	assume_ok(err)
	stderr_pipe[READ], stderr_pipe[WRITE], err = os2.pipe()
	assume_ok(err)

	desc: os2.Process_Desc = {
		env    = os2.environ(context.allocator),
		stdin  = stdin_pipe[READ],
		stdout = stdout_pipe[WRITE],
		stderr = stderr_pipe[WRITE],
	}

	program := `
	package auto
	import "core:fmt"
	import "core:os/os2"
	import "core:sys/linux"

	main :: proc() {
		buf: [32]u8

		n, err := os2.read(os2.stdin, buf[:])
		if err != nil {
			fmt.println(err)
			os2.exit(1)
		}
		if string(buf[:n]) != "GO!" { os2.exit(2) }

		n, err = os2.write_string(os2.stdout, "Hi there!")
		if err != nil { os2.exit(3) }
		n, err = os2.write_string(os2.stderr, "error channel")
		if err != nil { os2.exit(4) }
	}
	`
	p: os2.Process
	p, err = _run_background(program, &desc)
	assume_ok(err)

	assume_ok(os2.close(stdin_pipe[READ]))
	assume_ok(os2.close(stdout_pipe[WRITE]))
	assume_ok(os2.close(stderr_pipe[WRITE]))

	n: int
	n, err = os2.write_string(stdin_pipe[WRITE], "GO!")
	assume_ok(err)

	buf: [32]u8
	n, err = os2.read(stdout_pipe[READ], buf[:])
	assume_ok(err)
	assert(string(buf[:n]) == "Hi there!")

	n, err = os2.read(stderr_pipe[READ], buf[:])
	assume_ok(err)
	assert(string(buf[:n]) == "error channel")

	assert(_reap(&p) == 0)
	assume_ok(os2.remove("generated"))

	assume_ok(os2.close(stdin_pipe[WRITE]))
	assume_ok(os2.close(stdout_pipe[READ]))
	assume_ok(os2.close(stderr_pipe[READ]))
}

process_info :: proc() {
	selection: os2.Process_Info_Fields = {
		.Executable_Path,
		.PPid,
		.Priority,
		.Command_Line,
		.Command_Args,
		.Environment,
		.Username,
		.Working_Dir,
	}
	info, info_err := os2.process_info(selection, context.allocator)
	assume_ok(info_err)
	defer os2.free_process_info(info, context.allocator)

	assert(info.pid == os2.get_pid())
	assert(info.ppid == os2.get_ppid())

	list, err := os2.process_list(context.allocator)
	assume_ok(err)
	defer delete(list)

	fmt.println(list)
}

process_errors :: proc() {
	READ  :: 0
	WRITE :: 1

	File_Impl :: struct {
		file: os2.File,
		name: string,
		fd: linux.Fd,
		allocator: runtime.Allocator,

		buffer:   []byte,
		rw_mutex: sync.RW_Mutex, // read write calls
		p_mutex:  sync.Mutex, // pread pwrite calls
	}

	err: os2.Error
	stdin_pipe:  [2]^os2.File
	stdin_pipe[READ], stdin_pipe[WRITE], err = os2.pipe()
	assume_ok(err)

	impl := (^File_Impl)(rawptr(stdin_pipe[READ].impl))
	impl.fd = 2_000_000_000
	impl = (^File_Impl)(rawptr(stdin_pipe[WRITE].impl))
	impl.fd = 2_000_000_000

	desc: os2.Process_Desc = {
		env    = os2.environ(context.allocator),
		stdin  = stdin_pipe[READ],
	}

	program := `
	package auto
	import "core:fmt"
	main :: proc() { fmt.println("hello\n") }
	`
	p: os2.Process
	p, err = _run_background(program, &desc)
	expect_error(err, "child stdin dup fail")

}

process_waits :: proc() {
	desc: os2.Process_Desc = {
		command = {"./generated", "1", "2.0", "3"},
	}

	program := `
	package auto
	import "core:time"

	main :: proc() {
		start_tick := time.tick_now()
		for time.tick_since(start_tick) < 3 * time.Second { }
	}
	`
	p, err := _run_background(program, &desc)
	assume_ok(err)

	state: os2.Process_State
	state, err = os2.process_wait(p, 0)
	assume_ok(err)
	assert(!state.exited)

	fmt.println("after 0ms wait:", state.user_time, state.system_time)

	state, err = os2.process_wait(p, 200 * time.Millisecond)
	assume_ok(err)
	assert(!state.exited)

	fmt.println("after 200ms wait:", state.user_time, state.system_time)

	selection: os2.Process_Info_Fields = {
		.Executable_Path,
		.PPid,
		.Priority,
		.Command_Line,
		.Command_Args,
		.Environment,
		.Username,
		.Working_Dir,
	}
	info, info_err := os2.process_info(p, selection, context.allocator)
	assume_ok(info_err)
	fmt.println(info)

	state, err = os2.process_wait(p)
	assume_ok(err)
	assert(state.exited && state.success)

	fmt.println("after full wait (~3ms):", state.user_time, state.system_time)
}
