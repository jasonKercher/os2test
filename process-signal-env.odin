package os2test

import "base:runtime"

import    "core:fmt"
import    "core:sync"
import    "core:time"
import os "core:os/os2"
import    "core:sys/linux"

_gen_odin: [64]u8

_run_background :: proc(program: string, desc: ^os.Process_Desc = nil, loc := #caller_location) -> (os.Process, os.Error) {
	@static i := 0
	fmt.bprintf(_gen_odin[:], "generated%d.odin", i)
	i += 1

	f := create_write(string(_gen_odin[:]), program)
	assume_ok(os.close(f), loc)

	/* Build our program */
	{
		args := [?]string {"./odin", "build", string(_gen_odin[:]), "-file", "-out:generated"}
		odin_build_desc := os.Process_Desc {
			command = args[:],
			stderr  = os.stderr,
			stdout  = os.stdout,
		}

		odin_build, odin_err := os.process_start(odin_build_desc)
		assume_ok(odin_err, loc)
		if _reap(&odin_build) != 0 {
			fmt.println("Failed to build program at", loc)
			os.exit(2)
		}
	}

	/* Run our program */
	{
		args := [?]string { "./generated" }

		new_desc: os.Process_Desc
		if desc != nil {
			new_desc = desc^
		}

		if new_desc.command == nil {
			new_desc.command = args[:]
		}
		p, err := os.process_start(new_desc)
		return p, err
	}
}

_reap :: proc(process: ^os.Process, loc := #caller_location) -> int {
	state, err := os.process_wait(process^)
	assume_ok(err, loc)
	assert(state.exited, "", loc)
	//assume_ok(os.remove(string(_gen_odin[:])), loc)
	return state.exit_code
}

_run :: proc(program: string, desc: ^os.Process_Desc= nil, loc := #caller_location) -> int {
	p, err := _run_background(program, desc, loc)
	assume_ok(err, loc)
	return _reap(&p, loc)
}

env_basic :: proc() {
	val, found := os.lookup_env("DoEs-NoT-ExIsT", context.allocator)
	assert(!found)

	path: string
	path, found = os.lookup_env("PATH", context.allocator)
	assert(found)
	assert(len(path) != 0)

	env, err := os.environ(context.allocator)
	env_size := len(env)
	delete(env)

	os.set_env("os2_env_KEY", "VALUE")
	val, found = os.lookup_env("os2_env_KEY", context.allocator)
	assert(found)
	assert(val == "VALUE")

	env, err = os.environ(context.allocator)
	assert(len(env) == env_size + 1)
	delete(env)

	assert(os.unset_env("os2_env_KEY"))
	//assert(!os.unset_env("os2_env_KEY"))

	env, err = os.environ(context.allocator)
	defer delete(env)
	assert(len(env) == env_size)
}

process_env :: proc() {
	program := `
	package auto
	import os "core:os/os2"
	main :: proc() {
		res := 0
		env, err := os.environ(context.allocator)
		if len(env) <= 0 { os.exit(1) }
		os.clear_env()
		env, err = os.environ(context.allocator)
		if len(env) != 0 { os.exit(2) }
	}
	`
	assert(_run(program) == 0)

	org_env, err := os.environ(context.allocator)
	os.set_env("var_to_read_in_child", "child")
	/* should inherit our new var */
	program = `
	package auto
	import os "core:os/os2"
	main :: proc() {
		val, found := os.lookup_env("var_to_read_in_child", context.allocator)
		if !found { os.exit(1) }
		if val != "child" { os.exit(2) }assert(found && val == "child")
	}
	`
	assert(_run(program) == 0)

	desc: os.Process_Desc = {
		env = org_env,
	}

	assert(_run(program, &desc) != 0)
}

process_script :: proc() {
	f := create_write("nada.sh", "#!/bin/bash")
	assume_ok(os.fchmod(f, os.Permissions_All))
	os.close(f)

	desc: os.Process_Desc = {
		command = {"nada.sh"},
	}
	p, err := os.process_start(desc)
	assume_ok(err)

	state, wait_err := os.process_wait(p)
	assume_ok(wait_err)
	assert(state.exited)
	assert(state.success)
	assert(state.exit_code == 0)

	assume_ok(os.remove("nada.sh"))
}

process_pipes :: proc() {
	READ  :: 0
	WRITE :: 1

	stdin_pipe:  [2]^os.File
	stdout_pipe: [2]^os.File
	stderr_pipe: [2]^os.File

	err: os.Error

	stdin_pipe[READ], stdin_pipe[WRITE], err = os.pipe()
	assume_ok(err)
	stdout_pipe[READ], stdout_pipe[WRITE], err = os.pipe()
	assume_ok(err)
	stderr_pipe[READ], stderr_pipe[WRITE], err = os.pipe()
	assume_ok(err)

	env: []string
	env, err = os.environ(context.allocator)
	assume_ok(err)
	desc: os.Process_Desc = {
		env    = env,
		stdin  = stdin_pipe[READ],
		stdout = stdout_pipe[WRITE],
		stderr = stderr_pipe[WRITE],
	}

	program := `
	package auto
	import    "core:fmt"
	import os "core:os/os2"
	import    "core:sys/linux"

	main :: proc() {
		buf: [32]u8

		n, err := os.read(os.stdin, buf[:])
		if err != nil {
			fmt.println(err)
			os.exit(1)
		}
		if string(buf[:n]) != "GO!" { os.exit(2) }

		n, err = os.write_string(os.stdout, "Hi there!")
		if err != nil { os.exit(3) }
		n, err = os.write_string(os.stderr, "error channel")
		if err != nil { os.exit(4) }
	}
	`
	p: os.Process
	p, err = _run_background(program, &desc)
	assume_ok(err)

	assume_ok(os.close(stdin_pipe[READ]))
	assume_ok(os.close(stdout_pipe[WRITE]))
	assume_ok(os.close(stderr_pipe[WRITE]))

	n: int
	n, err = os.write_string(stdin_pipe[WRITE], "GO!")
	assume_ok(err)

	buf: [32]u8
	n, err = os.read(stdout_pipe[READ], buf[:])
	assume_ok(err)
	assert(string(buf[:n]) == "Hi there!")

	n, err = os.read(stderr_pipe[READ], buf[:])
	assume_ok(err)
	assert(string(buf[:n]) == "error channel")

	assert(_reap(&p) == 0)
	assume_ok(os.remove("generated"))

	assume_ok(os.close(stdin_pipe[WRITE]))
	assume_ok(os.close(stdout_pipe[READ]))
	assume_ok(os.close(stderr_pipe[READ]))
}

process_info :: proc() {
	selection: os.Process_Info_Fields = {
		.Executable_Path,
		.PPid,
		.Priority,
		.Command_Line,
		.Command_Args,
		.Environment,
		.Username,
		.Working_Dir,
	}
	info, info_err := os.process_info(selection, context.allocator)
	assume_ok(info_err)
	defer os.free_process_info(info, context.allocator)

	assert(info.pid == os.get_pid())
	assert(info.ppid == os.get_ppid())

	list, err := os.process_list(context.allocator)
	assume_ok(err)
	defer delete(list)

	fmt.println(list)
}

process_errors :: proc() {
	READ  :: 0
	WRITE :: 1

	File_Impl :: struct {
		file: os.File,
		name: string,
		fd: linux.Fd,
		allocator: runtime.Allocator,

		buffer:   []byte,
		rw_mutex: sync.RW_Mutex, // read write calls
		p_mutex:  sync.Mutex, // pread pwrite calls
	}

	err: os.Error
	stdin_pipe:  [2]^os.File
	stdin_pipe[READ], stdin_pipe[WRITE], err = os.pipe()
	assume_ok(err)

	impl := (^File_Impl)(rawptr(stdin_pipe[READ].impl))
	impl.fd = 2_000_000_000
	impl = (^File_Impl)(rawptr(stdin_pipe[WRITE].impl))
	impl.fd = 2_000_000_000

	env: []string
	env, err = os.environ(context.allocator)
	assume_ok(err)
	desc: os.Process_Desc = {
		env    = env,
		stdin  = stdin_pipe[READ],
	}

	program := `
	package auto
	import "core:fmt"
	main :: proc() { fmt.println("hello\n") }
	`
	p: os.Process
	p, err = _run_background(program, &desc)
	expect_error(err, "child stdin dup fail")

}

process_waits :: proc() {
	desc: os.Process_Desc = {
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

	state: os.Process_State
	state, err = os.process_wait(p, 0)
	assert(err == .Timeout)
	assert(!state.exited)

	fmt.println("after 0ms wait:", state.user_time, state.system_time)

	state, err = os.process_wait(p, 200 * time.Millisecond)
	assert(err == .Timeout)
	assert(!state.exited)

	fmt.println("after 200ms wait:", state.user_time, state.system_time)

	selection: os.Process_Info_Fields = {
		.Executable_Path,
		.PPid,
		.Priority,
		.Command_Line,
		.Command_Args,
		.Environment,
		.Username,
		.Working_Dir,
	}
	info, info_err := os.process_info(p, selection, context.allocator)
	assume_ok(info_err)
	fmt.println(info)

	state, err = os.process_wait(p)
	assume_ok(err)
	assert(state.exited && state.success)

	fmt.println("after full wait (~3ms):", state.user_time, state.system_time)
}
