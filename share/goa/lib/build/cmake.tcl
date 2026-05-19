proc _create_cmake_modules { } {
	global config::var_dir config::abi_dir api_dirs project_dir
	global cmake_module_dir 

	set cmake_module_dir [file join $var_dir cmake Modules]
	if {[file exists $cmake_module_dir]} {
		file delete -force $cmake_module_dir }

	file mkdir $cmake_module_dir

	# copy Find*.cmake files from api directories
	foreach api_dir $api_dirs {
		foreach cmake_file [glob -nocomplain $api_dir/Find*.cmake] {
			file copy $cmake_file $cmake_module_dir }
	}

	# find CMakeLists.txt files
	try {
		set cmake_list_files [exec find [file join $project_dir src] -name CMakeLists.txt]
	} trap CHILDSTATUS { } {
		set cmake_list_files ""
	} on error { msg } { error $msg $::errorInfo }

	# acquire used modules from all CMakeLists.txt
	set used_cmake_modules ""
	foreach cmake_list $cmake_list_files {
		try {
			append used_cmake_modules [exec grep find_package\( $cmake_list | sed -e {s/\s*find_package(\(\w*\).*).*/\1/}]
		} trap CHILDSTATUS { } {
		} on error { msg } { error $msg $::errorInfo }
	}

	#
	# create missing Find*.cmake files if corresponding api is used
	#
	# Note: We compare the lower-case package name used by cmake with the
	#       archive names mentioned in used_apis. More precisely, the archive
	#       name must end with the lower-case package name. If api archives
	#       provide differently named or multiple packages, they must come with
	#       corresponding Find*.cmake files.
	# 
	foreach package_name $used_cmake_modules {
		set cmake_file [file join $cmake_module_dir Find${package_name}.cmake]
		if {[file exists $cmake_file]} {
			continue }

		# quirk: pthread is provided by our libc
		if {$package_name == "Threads" && [using_api libc]} {
			set fd [open $cmake_file w]
			puts $fd "set(${package_name}_FOUND True)"
			puts $fd "set(CMAKE_USE_PTHREADS_INIT True)"
			close $fd
			continue
		}

		set api_dir [lsearch -inline -nocase -regexp $api_dirs /.*$package_name/*]
		if {$api_dir != ""} {
			set archive_name [lindex [split $api_dir "/"] end-1]
			diag "CMake module $package_name is provided by used $archive_name api"

			set fd [open $cmake_file w]
			puts $fd "set(${package_name}_FOUND True)"
			puts $fd "set(${package_name}_LIBRARY [file join $abi_dir $archive_name.lib.so])"
			puts $fd "set(${package_name}_INCLUDE_DIR [file join $api_dir include])"
			close $fd
		} else {
			log "CMake module $package_name is not provided by any api archive" \
			    "please consider adding the corresponding api archive to the used_apis file."

			set fd [open $cmake_file w]
			puts $fd "set(${package_name}_FOUND False)"
			close $fd
		}
	}
	return $cmake_module_dir
}


proc create_or_update_build_dir { } {

	global tool_dir
	global cppflags cflags cxxflags spec_args
	global env cmake_quirk_args
	global config::build_dir project_dir config::abi_dir
	global config::cross_dev_prefix project_name

	# check whether CMakeLists.txt modifies CMAKE_MODULE_PATH
	set     check_modules_cmd grep
	lappend check_modules_cmd set\(CMAKE_MODULE_PATH
	lappend check_modules_cmd [file join $project_dir src CMakeLists.txt]
	if {[exec_status $check_modules_cmd] == 0} {
		exit_with_error "src/CMakeLists.txt sets CMAKE_MODULE_PATH, which must be" \
		                "\nsolely managed by Goa. Please patch the file accordingly."
	}

	set cmake_module_dir [_create_cmake_modules]

	if {![file exists $build_dir]} {
		file mkdir $build_dir }

	create_spec_file "" ""

	set orig_pwd [pwd]
	cd $build_dir

	set     cmd [goa::sandboxed_build_command]
	lappend cmd cmake
	lappend cmd "-DCMAKE_IGNORE_PREFIX_PATH='/;/usr'"
	lappend cmd "-DCMAKE_MODULE_PATH='$cmake_module_dir;[file join $tool_dir cmake Modules]'"
	lappend cmd "-DCMAKE_SYSTEM_NAME=Genode"
	lappend cmd "-DCMAKE_C_COMPILER=${cross_dev_prefix}gcc"
	lappend cmd "-DCMAKE_CXX_COMPILER=${cross_dev_prefix}g++"
	lappend cmd "-DCMAKE_C_FLAGS='$cflags $cppflags'"
	lappend cmd "-DCMAKE_CXX_FLAGS='$cxxflags $cppflags'"
	lappend cmd "-DCMAKE_EXE_LINKER_FLAGS='$spec_args'"
	lappend cmd "-DCMAKE_SHARED_LINKER_FLAGS='$spec_args -shared'"
	lappend cmd "-DCMAKE_MODULE_LINKER_FLAGS='$spec_args -shared'"
	lappend cmd "-DCMAKE_INSTALL_PREFIX:PATH=[file join $build_dir install]"
	lappend cmd "-DCMAKE_SYSTEM_LIBRARY_PATH='$abi_dir'"

	if {[info exists cmake_quirk_args]} {
		foreach arg $cmake_quirk_args {
			lappend cmd $arg } }

	# add project-specific arguments read from 'cmake_args' file
	foreach arg [read_file_content_as_list [file join $project_dir cmake_args]] {
		lappend cmd $arg }

	lappend cmd [file join $project_dir src]

	diag "create build directory via cmake"

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via cmake failed:\n" $msg }

	cd $orig_pwd
}


proc build { } {
	global verbose tool_dir
	global config::build_dir config::jobs project_name

	set     cmd [goa::sandboxed_build_command]
	lappend cmd make -C $build_dir "-j$jobs"

	if {$verbose == 0} {
		lappend cmd "-s"
	} else {
		lappend cmd "VERBOSE=1"
	}

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "build via cmake failed:\n" $msg }

	# return if 'install' target does not exist
	if {[exec_status [list {*}$cmd -q install]] == 2} {
		return }

	# at this point, we know that the 'install' target exists
	lappend cmd install
	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "install via cmake failed:\n" $msg }
}
