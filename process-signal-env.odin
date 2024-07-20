package os2test

import "core:sys/linux"

import "core:fmt"
import "core:time"
import "core:os/os2"

_gen_odin: [64]u8

_run_background :: proc(program: string, desc: ^os2.Process_Desc = nil, loc := #caller_location) -> os2.Process {
	@static i := 0
	fmt.bprintf(_gen_odin[:], "generated%d.odin", i)
	i += 1

	f := create_write(string(_gen_odin[:]), program)
	assume_ok(os2.close(f), loc)

	args: [4]string = {"run", string(_gen_odin[:]), "-file", "-out:generated"}

	new_desc: os2.Process_Desc
	if desc != nil {
		new_desc = desc^
	}
	new_desc.command = args[:]

	p, err := os2.process_start(new_desc)
	assume_ok(err, loc)

	return p
}

_reap :: proc(process: ^os2.Process, loc := #caller_location) -> int {
	state, err := os2.process_wait(process^)
	assume_ok(err, loc)
	assert(state.exited, "", loc)
	assume_ok(os2.remove(string(_gen_odin[:])), loc)
	return state.exit_code
}

_run :: proc(program: string, desc: ^os2.Process_Desc= nil, loc := #caller_location) -> int {
	p := _run_background(program, desc, loc)
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
		env = org_env
	}

	assert(_run(program, &desc) != 0)
}


process_signals :: proc() {
	program := `
	package auto
	import "core:os/os2"
	import "core:time"

	ret := 5
	_sig_handler :: proc "c" (sig: i32) { ret = 0 }

	main :: proc() {
		handler: os2.Signal_Handler = os2.Signal_Handler_Proc(_sig_handler)
		os2.process_signal(.Interrupt, handler)
		time.sleep(time.Second)
		os2.exit(ret)
	}
	`

	p := _run_background(program)
	when ODIN_OS == .Linux {
		linux.kill(linux.Pid(p.pid), .SIGINT)
	} else {
		unimplemented("need windows impl...")
	}
	_reap(&p)

	p = _run_background(program)
	assume_ok(os2.process_kill(p))

	time.sleep(250 * time.Millisecond)

	state, err := os2.process_wait(p, time.Duration(0))
	assume_ok(err)
	assert(state.exited)
	assert(state.exit_code != 0)
	assume_ok(os2.remove(string(_gen_odin[:])))
}

process_pipes :: proc() {
	child_stdin:  os2.File
	child_stdout: os2.File
	child_stderr: os2.File

	// lol.. this api. Save me flysand!
	desc: os2.Process_Desc= {
		env = os2.environ(context.allocator),
		stdin  = &child_stdin,
		stdout = &child_stdout,
		stderr = &child_stderr,
	}

	program := `
	package auto
	import "core:os/os2"
	import "core:time"

	main :: proc() {
	      buf: [32]u8
	      n, err := os2.read(os2.stdin, buf[:])
	      if (err != nil) { os2.exit(1) }
	      if (string(buf[:n]) != "GO!") { os2.exit(2) }

	      n, err = os2.write_string(os2.stdout, "Hi there!")
	      if (err != nil) { os2.exit(3) }
	      n, err = os2.write_string(os2.stderr, "error channel")
	      if (err != nil) { os2.exit(4) }
	}
	`
	p := _run_background(program, &desc)

	n, err := os2.write_string(&child_stdin, "GO!")
	assume_ok(err)

	buf: [32]u8
	n, err = os2.read(&child_stdout, buf[:])
	assume_ok(err)
	assert(string(buf[:n]) == "Hi there!")

	n, err = os2.read(&child_stderr, buf[:])
	assume_ok(err)
	assert(string(buf[:n]) == "error channel")

	assert(_reap(&p) == 0)
	assume_ok(os2.remove("generated"))
}

process_waits :: proc() {
	sleep_argv: [5]string
	sleep_argc := 0
	// TODO: Easier to just write an Odin program here...
	when ODIN_OS == .Windows {
		sleep_argv[0] = "timeout"
		sleep_argv[1] = "/t"
		sleep_argc = 2
	} else {
		sleep_argv[0] = "sleep"
		sleep_argc = 1
	}

	sleep_argv[sleep_argc] = ".5"
	sleep_argc += 1

	desc: os2.Process_Desc = {
		command = sleep_argv[:sleep_argc]
	}

	p, err := os2.process_start(desc)
	assume_ok(err)

	state: os2.Process_State
	state, err = os2.process_wait(p, time.Millisecond * 100)
	assume_ok(err)
	assert(!state.exited)

	state, err = os2.process_wait(p)
	assume_ok(err)
	assert(state.exited && state.success)
}

