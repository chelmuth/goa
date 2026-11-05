#
# Create and populate 'var/pkgconfig' with adjusted
# *.pc files that contain the proper include path and shared-library.
#
proc create_pkgconfig_dir { } {
	global config::var_dir api_dirs
	global pkgconfig_dir

	set pkgconfig_dir [file join $var_dir pkgconfig]
	if {[file exists $pkgconfig_dir]} {
		file delete -force $pkgconfig_dir }

	file mkdir $pkgconfig_dir

	diag "Create pkgconfig directory: $pkgconfig_dir"

	foreach api_dir $api_dirs {
		foreach pc_file [glob -nocomplain $api_dir/*.pc] {
			set installed_pc_file [file join $pkgconfig_dir [file tail $pc_file]]
			exec sed "s;DEPOT_API_DIR;$api_dir;g" $pc_file > $installed_pc_file } }

	return $pkgconfig_dir
}

proc query_pkgconfig_exact { pkgconfig_dir packagename flag } {

	set cmd [goa::sandboxed_build_command]

	lappend cmd --setenv PKG_CONFIG_LIBDIR "''"
	lappend cmd --setenv PKG_CONFIG_PATH "$pkgconfig_dir"

	#
	# For now hard-code a call to the build-host's pkg-config
	# executable as it seems to be used anyway as fallback when the
	# proper script, e.g. aarch64-elf-pkg-config or
	# x86_64-pc-elf-pkg-config in our case, cannot be found.
	#
	lappend cmd "pkg-config"

	# prevent noise due to non-exact checks (see below)
	lappend cmd "--silence-errors"

	lappend cmd "$flag"
	lappend cmd "$packagename"

	set success 0
	if {[catch {exec -ignorestderr {*}$cmd} msg] == 0} {
		set success 1
	}

	if {$success == 1} {
		# when --verbose is enabled the msg contains more than
		# the actual result string
		set result [lindex [split $msg "\n"] end]
		return $result
	}
	return ""
}

proc query_pkgconfig { pkgconfig_dir packagename flag } {

	set result [query_pkgconfig_exact "$pkgconfig_dir" "$packagename" "$flag"]
	# try again with lower-cases, e.g. SDL2 -> sdl2
	if {$result == ""} {
		set result [query_pkgconfig_exact "$pkgconfig_dir" "[string tolower $packagename]" "$flag"]
	}
	if {$result == ""} {
		log "Could not query $flag for $packagename, build might fail"
	}
	return $result
}
