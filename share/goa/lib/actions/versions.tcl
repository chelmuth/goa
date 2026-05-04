#used_apis#
# Version-related actions (require project directory)
#

namespace eval goa {
	namespace export archive-versions bump-version from-index used_apis

	##
	# Return list of versioned archives referenced by used_apis file
	# 
	proc used_apis { } {

		global   genodelabs
		variable _used_apis

		if {![info exists _used_apis]} {
			set _used_apis [apply_versions [read_file_content_as_list used_apis]]

			# replace 'genodelabs' with $genodelabs (overwritten by --genodelabs-user)
			set _used_apis [lmap a $_used_apis { regsub genodelabs/ $a $genodelabs/ }]

			if {[llength $_used_apis] > 0} {
				diag "used APIs: $_used_apis" }
		}

		return $_used_apis
	}


	##
	# Return list of unversioned archives referenced by pkg/archives file
	# 
	proc archives { } {

		global   genodelabs
		variable _archives

		if {![info exists _archives]} {
			set _archives [read_file_content_as_list [file join pkg archives]]

			# replace 'genodelabs' with $genodelabs (overwritten by --genodelabs-user)
			set _archives [lmap a $_archives { regsub genodelabs/ $a $genodelabs/ }]
		}

		return $_archives
	}


	proc _bump_with_suffix { target_version current_version } {
		
		if {[string first $target_version $current_version] == 0} {
			set elements [split $current_version -]
			set suffix [lindex $elements end]
			if {[llength $elements] > 3 && [regexp {[a-y]} $suffix dummy]} {
				# bump suffix
				set new_suffix [format %c [expr [scan $suffix %c]+1]]
				set target_version [join [lreplace $elements end end $new_suffix] -]
			} else {
				# add suffix
				set target_version "$current_version-a"
			}
		}

		return $target_version
	}


	proc _for_each_archive_type { &type body } {
		global project_dir

		upvar ${&type} type
		
		set api_file [file join $project_dir api]
		if {[file exists $api_file] && [file isfile $api_file]} {
			set type "api"
			uplevel 1 $body
		}

		set src_dir [file join $project_dir src]
		if {[file exists $src_dir] && [file isdirectory $src_dir]} {
			set type "src"
			uplevel 1 $body
		}

		set raw_dir [file join $project_dir raw]
		if {[file exists $raw_dir] && [file isdirectory $raw_dir]} {
			set type "raw"
			uplevel 1 $body
		}

		set pkg_dir [file join $project_dir pkg]
		if {[file exists $pkg_dir] && [file isdirectory $pkg_dir]} {
			set type "pkg"
			uplevel 1 $body
		}
	}
	

	proc bump-version { if_needed target_version } {

		global project_dir project_name
		global config::depot_user config::version

		set version_file [file join $project_dir version]

		# check whether any version is managed via goarc
		set any_version_set false
		if {![file exists $version_file]} {
			_for_each_archive_type type {
				if {[info exists version($depot_user/$type/$project_name)]} {
					set any_version_set true }
				if {[info exists version(_/$type/$project_name)]} {
					set any_version_set true }
			}
		}

		# return if version from version file has already been exported
		if {[file exists $version_file]} {
			if {$if_needed} {
				set dummy {}
				set status [expr [goa compare-src dummy] && \
				                 [goa compare-raw dummy] && \
				                 [goa compare-api dummy] && \
				                 [goa compare-pkg dummy]]

				if {$status} {
					log "Skipping version bump"
					return
				} else {
					log "Version update required"
				}
			}
		}

		# bump version in 'version' file
		if {[file exists $version_file] || !$any_version_set} {

			try {
				set old_version [project_version_from_file $project_dir]
			} trap NOT_FOUND { } {
				set old_version ""
			} on error { msg }   { error $msg $::errorInfo }

			set target_version [_bump_with_suffix $target_version $old_version]

			set fd [open $version_file w]
			puts $fd $target_version
			close $fd

			return
		}

		# print new versions if versions are managed via goarc
		if {$any_version_set} {
			_for_each_archive_type type {
				set skip_bump false
				if {$if_needed} {
					set dummy {}
					set skip_bump [goa compare-$type dummy]
				}

				set archive "$depot_user/$type/$project_name"
				set archive_version [archive_version [apply_versions $archive]]
				if {!$skip_bump} {
					set archive_version [_bump_with_suffix $target_version $archive_version]}

				log "set version($archive) $archive_version"
			}
		}
	}


	##
	# Get a list of archive+arch-list pairs from an index file for the given
	# archive type.
	#
	proc from-index { index_file args } {
		# get supported archs
		set supported_archs [query attributes $index_file "index | + supports | : arch"]
		if {[llength $supported_archs] == 0} {
			exit_with_error "missing '+ supports arch: ...' in index file" }

		# helper for recursive processing of index nodes
		proc _index_with_arch { node archs result args } {
			global ::config::depot_user

			set types $args
			node for-all-nodes $node type subnode {
				if {$type == "index"} {
					node with-attribute $subnode "arch" value {
						set archs [list $value]
					} default { }

					set result [_index_with_arch $subnode $archs $result {*}$types]
				}

				if {[lsearch -exact $types $type] < 0} {
					continue }

				node with-attribute $subnode "arch" value {
					set subarchs [list $value]
				} default {
					set subarchs $archs
				}

				node with-attribute $subnode "name" value {
					try {
						archive_user $value
					} trap INVALID_ARCHIVE { } {
						set value $depot_user/$type/$value
					} on error { msg } { error $msg $::errorInfo }
					
					lappend result $value $subarchs
				} with-attribute $subnode "path" value {
					try {
						archive_user $value
					} trap INVALID_ARCHIVE { } {
						set value $depot_user/$type/$value
					} on error { msg } { error $msg $::errorInfo }
				
					lappend result $value $subarchs
				} default {
					exit_with_error "Missing name attribute for '$type' node in index file"
				}
			}

			return $result
		}

		return [_index_with_arch [query node $index_file "index"] $supported_archs "" {*}$args]
	}


	proc archive-versions { archives } {

		global config::versions_from_genode_dir config::depot_user config::version
		global project_dir

		if {[llength $archives] > 0} {
			set versioned_archives [apply_versions $archives]
			foreach a $archives v $versioned_archives {
				set vers [archive_version $v]
				puts "set version($a) $vers"
			}
			exit
		}

		if {[info exists versions_from_genode_dir]} {

			puts "#\n# depot-archive versions from $versions_from_genode_dir\n#"
			set repos [glob -nocomplain [file join $versions_from_genode_dir repos *]]
			foreach rep_dir $repos {
				set hash_files [glob -nocomplain [file join $rep_dir recipes * * hash]]
				if {[llength $hash_files] > 0} {
					puts "\n# repos/[file tail $rep_dir]"
					set lines { }
					foreach hash_file $hash_files {
						set name [file tail [file dirname $hash_file]]
						set type [file tail [file dirname [file dirname $hash_file]]]
						set vers [lindex [read_file_content $hash_file] 0]
						lappend lines "set version($depot_user/$type/$name) $vers"
					}
					set lines [lsort $lines]
					foreach line $lines {
						puts "$line"
					}
				}
			}
		}

		if {[looks_like_goa_project_dir $project_dir]} {
			puts "\n#\n# depot-archive versions referenced by $project_dir\n#"
			set archives [read_file_content_as_list used_apis]
			set archives [concat $archives [read_file_content_as_list [file join pkg archives]]]

			set index_file [file join $project_dir index]
			if {[file exists $index_file] && [info exists depot_user]} {
				foreach { pkg_name pkg_archs } [from-index $index_file "pkg" "src" "api"] {
					lappend archives $pkg_name }
			}

			set archives [lsort -unique $archives]
			# Note: omitting 'validate_archives' because 'apply_versions' does it
			set versioned_archives [apply_versions $archives]
			foreach a $archives v $versioned_archives {
				set vers [archive_version $v]
				puts "set version($a) $vers"
			}
		}

		puts "\n#\n# additional depot-archive versions from goarc\n#"
		if {[info exists version]} {
			foreach archive [array names version] {
				if {[lsearch -exact $archives $archive] < 0} {
					puts "set version($archive) $version($archive)" } } }
		puts ""
	}
}
