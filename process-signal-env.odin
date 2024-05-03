package os2test

import "core:sys/linux"

import "core:fmt"
import "core:time"
import "core:os/os2"

_run_background :: proc(program: string, env: []string = {}, loc := #caller_location) -> os2.Process {
	f := create_write("generated.odin", program)
	assume_ok(os2.close(f), loc)

	args: [4]string = {"run", "generated.odin", "-file", "-debug"}

	attr: ^os2.Process_Attributes
	if len(env) > 0 {
		a: os2.Process_Attributes = { env = env }
		attr = &a
	}

	when ODIN_ARCH == .amd64 {
		odin_exe := "Odin/odin-amd64"
	} else when ODIN_ARCH == .arm64 {
		odin_exe := "Odin/odin-arm64"
	} else when ODIN_ARCH == .arm32 {
		odin_exe := "Odin/odin-arm"
	} else when ODIN_ARCH == .i386 {
		odin_exe := "Odin/odin-i386"
	}
	p, err := os2.process_start(odin_exe, args[:], attr)
	assume_ok(err, loc)

	return p
}

_reap :: proc(process: ^os2.Process, loc := #caller_location) -> int {
	state, err := os2.process_wait(process)
	assume_ok(err, loc)
	assert(bool(process.is_done), "", loc)
	assume_ok(os2.remove("generated.odin"), loc)
	return state.exit_code
}

_run :: proc(program: string, env: []string = {}, loc := #caller_location) -> int {
	p := _run_background(program, env, loc)
	return _reap(&p, loc)
}

env_basic :: proc() {
	val, found := os2.lookup_env("DoEs-NoT-ExIsT")
	assert(!found)

	path: string
	path, found = os2.lookup_env("PATH")
	assert(found)
	assert(len(path) != 0)

	env := os2.environ()
	env_size := len(env)
	delete(env)

	os2.set_env("os2_env_KEY", "VALUE")
	val, found = os2.lookup_env("os2_env_KEY")
	assert(found)
	assert(val == "VALUE")

	env = os2.environ()
	assert(len(env) == env_size + 1)
	delete(env)

	assert(os2.unset_env("os2_env_KEY"))
	assert(!os2.unset_env("os2_env_KEY"))

	env = os2.environ()
	defer delete(env)
	assert(len(env) == env_size)
}

process_waits :: proc() {
	sleep_argv: [5]string
	sleep_argc := 0
	when ODIN_OS == .Windows {
		sleep_exe := "timeout"
		sleep_argv[sleep_argc] = "/t"
		sleep_argc += 1
	} else {
		sleep_exe := "sleep"
	}

	sleep_argv[sleep_argc] = ".5"
	sleep_argc += 1

	p, err := os2.process_start(sleep_exe, sleep_argv[:sleep_argc])
	assume_ok(err)

	state: os2.Process_State
	state, err = os2.process_wait(&p, time.Millisecond * 100)
	assume_ok(err)
	assert(!state.exited)

	state, err = os2.process_wait(&p)
	assume_ok(err)
	assert(state.exited && state.success)
}

process_env :: proc() {
	program := `
	package auto
	import "core:os/os2"
	main :: proc() {
		env := os2.environ()
		assert(len(env) > 0)
		os2.clear_env()
		env = os2.environ()
		assert(len(env) == 0)
	}
	`
	assert(_run(program) == 0)

	org_env := os2.environ()
	os2.set_env("var_to_read_in_child", "child")
	/* should inherit our new var */
	program = `
	package auto
	import "core:os/os2"
	main :: proc() {
		val, found := os2.lookup_env("var_to_read_in_child")
		assert(found && val == "child")
	}
	`
	assert(_run(program) == 0)

	fmt.print("Expecting Error: ")
	assert(_run(program, org_env) != 0)
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
	assume_ok(os2.process_kill(&p))

	state, err := os2.process_wait(&p, time.Duration(0))
	assume_ok(err)
	assert(bool(p.is_done))
	assert(state.exit_code != 0)
}

process_pipes :: proc() {
	// TODO
}
