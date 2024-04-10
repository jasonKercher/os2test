package os2test

import "core:fmt"
import "core:time"
import "core:os/os2"

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

	/* sleep for 3 seconds */
	sleep_argv[sleep_argc] = "2"
	sleep_argc += 1

	p, err := os2.process_start(sleep_exe, sleep_argv[:sleep_argc])
	assume_ok(err)

	state: os2.Process_State
	state, err = os2.process_wait(&p, time.Millisecond * 500)
	assume_ok(err)
	assert(!state.exited)

	state, err = os2.process_wait(&p)
	assume_ok(err)
	assert(state.exited && state.success)

	fmt.println(state)
}

process_env :: proc() {
	program := `
	package autogenerated
	import "core:os/os2"
	main :: proc() { os2.write_string(os2.stdout, "hello\n") }
	`

	//os2.clear_env()
	//cleared := os2.environ()
	//defer delete(cleared)
	//assert(len(cleared) == 0)

	f := create_write("generated.odin", program)
	assume_ok(os2.close(f))
	defer os2.remove("generated.odin")

	p, err := os2.process_start("Odin/odin-native", {"run", "generated.odin", "-file", "-out:env_test"})
	assume_ok(err)

	state: os2.Process_State
	state, err = os2.process_wait(&p)
	assume_ok(err)
	assert(state.exited && state.exit_code == 0)
	defer os2.remove("env_test")
}

process_signals :: proc() {
}

