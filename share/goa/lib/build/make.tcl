proc _make_cmd { } {
	global verbose
	global cppflags cflags cxxflags api_dirs
	global spec_args
	global config::build_dir config::cross_dev_prefix config::jobs project_dir
	global config::depot_dir config::var_dir

	create_spec_file "" ""

	set     cmd [sandboxed_build_command]

	lappend cmd make -C $build_dir
	lappend cmd "CPPFLAGS=$cppflags"
	lappend cmd "CFLAGS=$cflags"
	lappend cmd "CXXFLAGS=$cxxflags"
	lappend cmd "CXX=$cross_dev_prefix\g++ $spec_args"
	lappend cmd "CC=$cross_dev_prefix\gcc $spec_args"
	lappend cmd "CROSS_DEV_PREFIX=$cross_dev_prefix"
	lappend cmd "-j$jobs"
	lappend cmd "PKG_CONFIG_LIBDIR=''"
	lappend cmd "PKG_CONFIG_PATH=[join ${api_dirs} ":"]"

	# keep MAKE_SHARED_LINKER_FLAGS for backward compatibility (replace by specs)
	lappend cmd "MAKE_SHARED_LINKER_FLAGS=-shared"

	if {$verbose == 0} {
		lappend cmd "-s" }

	# add project-specific arguments read from 'make_args' file
	foreach arg [read_file_content_as_list [file join $project_dir make_args]] {
		lappend cmd $arg }

	return $cmd
}


proc create_or_update_build_dir { } {
	global config::build_dir spec_file

	# compare make command and link spec, and clear directory if anything changed
	set signature_file [file join $build_dir ".goa_make_command"]

	set previous_cmd       [string trim [read_file_content $signature_file]]
	set previous_link_spec [string trim [read_file_content $spec_file]]

	set cmd       [join [_make_cmd] { }]
	set link_spec [string trim [read_file_content $spec_file]]

	if {"$previous_cmd" != "$cmd" || "$previous_link_spec" != "$link_spec"} {
		file delete -force $build_dir
	}

	mirror_source_dir_to_build_dir

	# write build command to file
	set fd [open $signature_file w]
	puts $fd $cmd
	close $fd
}


proc build { } {
	global project_name

	set cmd [_make_cmd]

	# skip make (and make install) if there is nothing to be made
	if {[exec_status [list {*}$cmd -q]] == 0} {
		diag "everything is up to date"
		return
	}

	diag "build via command" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:make\] /" >@ stdout}]} {
		exit_with_error "build via make failed" }

	# return if 'install' target does not exist
	if {[exec_status [list {*}$cmd -q install]] == 2} {
		return }

	# at this point, we know that the 'install' target exists
	lappend cmd install
	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:make\] /" >@ stdout}]} {
		exit_with_error "install via make failed"  }
}
