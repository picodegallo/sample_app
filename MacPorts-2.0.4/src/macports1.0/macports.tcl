# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:filetype=tcl:et:sw=4:ts=4:sts=4
# macports.tcl
# $Id: macports.tcl 90156 2012-02-24 12:30:34Z jmr@macports.org $
#
# Copyright (c) 2002 - 2003 Apple Inc.
# Copyright (c) 2004 - 2005 Paul Guyot, <pguyot@kallisys.net>.
# Copyright (c) 2004 - 2006 Ole Guldberg Jensen <olegb@opendarwin.org>.
# Copyright (c) 2004 - 2005 Robert Shaw <rshaw@opendarwin.org>
# Copyright (c) 2004 - 2012 The MacPorts Project
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of Apple Inc. nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
package provide macports 1.0
package require macports_dlist 1.0
package require macports_index 1.0
package require macports_util 1.0

namespace eval macports {
    namespace export bootstrap_options user_options portinterp_options open_mports ui_priorities port_phases 
    variable bootstrap_options "\
        portdbpath libpath binpath auto_path extra_env sources_conf prefix portdbformat \
        portarchivetype portautoclean \
        porttrace portverbose keeplogs destroot_umask variants_conf rsync_server rsync_options \
        rsync_dir startupitem_type place_worksymlink xcodeversion xcodebuildcmd \
        mp_remote_url mp_remote_submit_url configureccache ccache_dir ccache_size configuredistcc configurepipe buildnicevalue buildmakejobs \
        applications_dir frameworks_dir developer_dir universal_archs build_arch macosx_deployment_target \
        macportsuser proxy_override_env proxy_http proxy_https proxy_ftp proxy_rsync proxy_skip \
        master_site_local patch_site_local archive_site_local packagemaker_path"
    variable user_options "submitter_name submitter_email submitter_key"
    variable portinterp_options "\
        portdbpath porturl portpath portbuildpath auto_path prefix prefix_frozen portsharepath \
        registry.path registry.format user_home \
        portarchivetype archivefetch_pubkeys portautoclean porttrace keeplogs portverbose destroot_umask \
        rsync_server rsync_options rsync_dir startupitem_type place_worksymlink macportsuser \
        mp_remote_url mp_remote_submit_url configureccache ccache_dir ccache_size configuredistcc configurepipe buildnicevalue buildmakejobs \
        applications_dir current_phase frameworks_dir developer_dir universal_archs build_arch \
        os_arch os_endian os_version os_major os_platform macosx_version macosx_deployment_target \
        packagemaker_path $user_options"

    # deferred options are only computed when needed.
    # they are not exported to the trace thread.
    # they are not exported to the interpreter in system_options array.
    variable portinterp_deferred_options "xcodeversion xcodebuildcmd"

    variable open_mports {}

    variable ui_priorities "error warn msg notice info debug any"
    variable port_phases "any fetch checksum"
    variable current_phase "main"
}

# Provided UI instantiations
# For standard messages, the following priorities are defined
#     debug, info, msg, warn, error
# Clients of the library are expected to provide ui_prefix and ui_channels with
# the following prototypes.
#     proc ui_prefix {priority}
#     proc ui_channels {priority}
# ui_prefix returns the prefix for the messages, if any.
# ui_channels returns a list of channels to output the message to, empty for
#     no message.
# if these functions are not provided, defaults are used.
# Clients of the library may optionally provide ui_init with the following
# prototype.
#     proc ui_init {priority prefix channels message}
# ui_init needs to correctly define the proc ::ui_$priority {message} or throw
# an error.
# if this function is not provided or throws an error, default procedures for
# ui_$priority are defined.

# ui_options accessor
proc macports::ui_isset {val} {
    if {[info exists macports::ui_options($val)]} {
        if {$macports::ui_options($val) == "yes"} {
            return 1
        }
    }
    return 0
}


# global_options accessor
proc macports::global_option_isset {val} {
    if {[info exists macports::global_options($val)]} {
        if {$macports::global_options($val) == "yes"} {
            return 1
        }
    }
    return 0
}

proc macports::init_logging {mport} {
    global macports::channels macports::portdbpath

    if {[getuid] == 0 && [geteuid] != 0} {
        seteuid 0; setegid 0
    }
    if {[catch {macports::ch_logging $mport} err]} {
        ui_debug "Logging disabled, error opening log file: $err"
        return 1
    }
    # Add our log-channel to all already initialized channels
    foreach key [array names channels] {
        set macports::channels($key) [concat $macports::channels($key) "debuglog"]
    }
    return 0
}
proc macports::ch_logging {mport} {
    global ::debuglog ::debuglogname

    set portname [_mportkey $mport subport]
    set portpath [_mportkey $mport portpath]

    ui_debug "Starting logging for $portname"

    set logname [macports::getportlogpath $portpath $portname]
    file mkdir $logname
    set logname [file join $logname "main.log"]

    set ::debuglogname $logname

    # Truncate the file if already exists
    set ::debuglog [open $::debuglogname w]
    puts $::debuglog "version:1"
}
proc macports::push_log {mport} {
    global ::logstack ::logenabled ::debuglog ::debuglogname
    if {![info exists ::logenabled]} {
        if {[macports::init_logging $mport] == 0} {
            set ::logenabled yes
            set ::logstack [list [list $::debuglog $::debuglogname]]
            return
        } else {
            set ::logenabled no
        }
    }
    if {$::logenabled} {
        if {[getuid] == 0 && [geteuid] != 0} {
            seteuid 0; setegid 0
        }
        if {[catch {macports::ch_logging $mport} err]} {
            ui_debug "Logging disabled, error opening log file: $err"
            return
        }
        lappend ::logstack [list $::debuglog $::debuglogname]
    }
}
proc macports::pop_log {} {
    global ::logenabled ::logstack ::debuglog ::debuglogname
    if {![info exists ::logenabled]} {
        return -code error "pop_log called before push_log"
    }
    if {$::logenabled && [llength $::logstack] > 0} {
        close $::debuglog
        set ::logstack [lreplace $::logstack end end]
        if {[llength $::logstack] > 0} {
            set top [lindex $::logstack end]
            set ::debuglog [lindex $top 0]
            set ::debuglogname [lindex $top 1]
        } else {
            unset ::debuglog
            unset ::debuglogname
        }
    }
}

proc set_phase {phase} {
    global macports::current_phase
    set macports::current_phase $phase
    if {$phase != "main"} {
        set cur_time [clock format [clock seconds] -format  {%+}]
        ui_debug "$phase phase started at $cur_time"
    }
}

proc ui_message {priority prefix phase args} {
    global macports::channels ::debuglog macports::current_phase
    foreach chan $macports::channels($priority) {
        if {[info exists ::debuglog] && ($chan == "debuglog")} {
            set chan $::debuglog
            if {[info exists macports::current_phase]} {
                set phase $macports::current_phase
            }
            set strprefix ":$priority:$phase "
            if {[lindex $args 0] == "-nonewline"} {
                puts -nonewline $chan "$strprefix[lindex $args 1]"
            } else {
                puts $chan "$strprefix[lindex $args 0]"
            }
 
        } else {
            if {[lindex $args 0] == "-nonewline"} {
                puts -nonewline $chan "$prefix[lindex $args 1]"
            } else {
                puts $chan "$prefix[lindex $args 0]"
            }
        }
    }
}
proc macports::ui_init {priority args} {
    global macports::channels ::debuglog
    set default_channel [macports::ui_channels_default $priority]
    # Get the list of channels.
    if {[llength [info commands ui_channels]] > 0} {
        set channels($priority) [ui_channels $priority]
    } else {
        set channels($priority) $default_channel
    }
    
    # if some priority initialized after log file is being created
    if {[info exists ::debuglog]} {
        set channels($priority) [concat $channels($priority) "debuglog"]
    }
    # Simplify ui_$priority.
    try {
        set prefix [ui_prefix $priority]
    } catch * {
        set prefix [ui_prefix_default $priority]
    }
    set phases {fetch checksum}
    try {
        eval ::ui_init $priority $prefix $channels($priority) $args
    } catch * {
        interp alias {} ui_$priority {} ui_message $priority $prefix ""
        foreach phase $phases {
            interp alias {} ui_${priority}_${phase} {} ui_message $priority $prefix $phase
        }
    }
}

# Default implementation of ui_prefix
proc macports::ui_prefix_default {priority} {
    switch $priority {
        debug {
            return "DEBUG: "
        }
        error {
            return "Error: "
        }
        warn {
            return "Warning: "
        }
        default {
            return ""
        }
    }
}

# Default implementation of ui_channels:
# ui_options(ports_debug) - If set, output debugging messages
# ui_options(ports_verbose) - If set, output info messages (ui_info)
# ui_options(ports_quiet) - If set, don't output "standard messages"
proc macports::ui_channels_default {priority} {
    switch $priority {
        debug {
            if {[ui_isset ports_debug]} {
                return {stderr}
            } else {
                return {}
            }
        }
        info {
            if {[ui_isset ports_verbose]} {
                return {stdout}
            } else {
                return {}
            }
        }
        notice {
            if {[ui_isset ports_quiet]} {
                return {}
            } else {
                return {stdout}
            }
        }
        msg {
            return {stdout}
        }
        warn -
        error {
            return {stderr}
        }
        default {
            return {stdout}
        }
    }
}

proc ui_warn_once {id msg} {
    variable macports::warning_done
    if {![info exists macports::warning_done($id)]} {
        ui_warn $msg
        set macports::warning_done($id) 1
    }
}

# Replace puts to catch errors (typically broken pipes when being piped to head)
rename puts tcl::puts
proc puts {args} {
    catch "tcl::puts $args"
}

# find a binary either in a path defined at MacPorts' configuration time
# or in the PATH environment variable through macports::binaryInPath (fallback)
proc macports::findBinary {prog {autoconf_hint ""}} {
    if {${autoconf_hint} != "" && [file executable ${autoconf_hint}]} {
        return ${autoconf_hint}
    } else {
        if {[catch {set cmd_path [macports::binaryInPath ${prog}]} result] == 0} {
            return ${cmd_path}
        } else {
            return -code error "${result} or at its MacPorts configuration time location, did you move it?"
        }
    }
}

# check for a binary in the path
# returns an error code if it cannot be found
proc macports::binaryInPath {prog} {
    global env
    foreach dir [split $env(PATH) :] {
        if {[file executable [file join $dir $prog]]} {
            return [file join $dir $prog]
        }
    }
    return -code error [format [msgcat::mc "Failed to locate '%s' in path: '%s'"] $prog $env(PATH)];
}

# deferred option processing
proc macports::getoption {name} {
    global macports::$name
    return [expr $$name]
}

# deferred and on-need extraction of xcodeversion and xcodebuildcmd.
proc macports::setxcodeinfo {name1 name2 op} {
    global macports::xcodeversion
    global macports::xcodebuildcmd

    trace remove variable macports::xcodeversion read macports::setxcodeinfo
    trace remove variable macports::xcodebuildcmd read macports::setxcodeinfo

    if {[catch {set xcodebuild [binaryInPath "xcodebuild"]}] == 0} {
        if {![info exists xcodeversion]} {
            # Determine xcode version
            set macports::xcodeversion "2.0orlower"
            if {[catch {set xcodebuildversion [exec -- $xcodebuild -version 2> /dev/null]}] == 0} {
                if {[regexp {Xcode ([0-9.]+)} $xcodebuildversion - xcode_v] == 1} {
                    set macports::xcodeversion $xcode_v
                } elseif {[regexp "DevToolsCore-(.*);" $xcodebuildversion - devtoolscore_v] == 1} {
                    if {$devtoolscore_v >= 1809.0} {
                        set macports::xcodeversion "3.2.6"
                    } elseif {$devtoolscore_v >= 1204.0} {
                        set macports::xcodeversion "3.1.4"
                    } elseif {$devtoolscore_v >= 1100.0} {
                        set macports::xcodeversion "3.1"
                    } elseif {$devtoolscore_v >= 921.0} {
                        set macports::xcodeversion "3.0"
                    } elseif {$devtoolscore_v >= 798.0} {
                        set macports::xcodeversion "2.5"
                    } elseif {$devtoolscore_v >= 762.0} {
                        set macports::xcodeversion "2.4.1"
                    } elseif {$devtoolscore_v >= 757.0} {
                        set macports::xcodeversion "2.4"
                    } elseif {$devtoolscore_v > 650.0} {
                        # XXX find actual version corresponding to 2.3
                        set macports::xcodeversion "2.3"
                    } elseif {$devtoolscore_v >= 650.0} {
                        set macports::xcodeversion "2.2.1"
                    } elseif {$devtoolscore_v > 620.0} {
                        # XXX find actual version corresponding to 2.2
                        set macports::xcodeversion "2.2"
                    } elseif {$devtoolscore_v >= 620.0} {
                        set macports::xcodeversion "2.1"
                    }
                }
            } else {
                ui_warn "xcodebuild exists but failed to execute"
                set macports::xcodeversion "none"
            }
        }
        if {![info exists xcodebuildcmd]} {
            set macports::xcodebuildcmd "$xcodebuild"
        }
    } else {
        if {![info exists xcodeversion]} {
            set macports::xcodeversion "none"
        }
        if {![info exists xcodebuildcmd]} {
            set macports::xcodebuildcmd "none"
        }
    }
}

proc mportinit {{up_ui_options {}} {up_options {}} {up_variations {}}} {
    if {$up_ui_options eq ""} {
        array set macports::ui_options {}
    } else {
        upvar $up_ui_options temp_ui_options
        array set macports::ui_options [array get temp_ui_options]
    }
    if {$up_options eq ""} {
        array set macports::global_options {}
    } else {
        upvar $up_options temp_options
        array set macports::global_options [array get temp_options]
    }
    if {$up_variations eq ""} {
        array set variations {}
    } else {
        upvar $up_variations variations
    }

    # Initialize ui_*
    foreach priority ${macports::ui_priorities} {
        macports::ui_init $priority
    }

    global auto_path env tcl_platform
    global macports::autoconf::macports_conf_path
    global macports::macports_user_dir
    global macports::bootstrap_options
    global macports::user_options
    global macports::extra_env
    global macports::portconf
    global macports::portdbpath
    global macports::portsharepath
    global macports::registry.format
    global macports::registry.path
    global macports::sources
    global macports::sources_default
    global macports::sources_conf
    global macports::destroot_umask
    global macports::libpath
    global macports::prefix
    global macports::macportsuser
    global macports::prefix_frozen
    global macports::rsync_dir
    global macports::rsync_options
    global macports::rsync_server
    global macports::variants_conf
    global macports::xcodebuildcmd
    global macports::xcodeversion
    global macports::configureccache
    global macports::ccache_dir
    global macports::ccache_size
    global macports::configuredistcc
    global macports::configurepipe
    global macports::buildnicevalue
    global macports::buildmakejobs
    global macports::universal_archs
    global macports::build_arch
    global macports::os_arch
    global macports::os_endian
    global macports::os_version
    global macports::os_major
    global macports::os_platform
    global macports::macosx_version
    global macports::macosx_deployment_target
    global macports::archivefetch_pubkeys

    # Set the system encoding to utf-8
    encoding system utf-8

    # set up platform info variables
    set os_arch $tcl_platform(machine)
    if {$os_arch == "Power Macintosh"} { set os_arch "powerpc" }
    if {$os_arch == "i586" || $os_arch == "i686" || $os_arch == "x86_64"} { set os_arch "i386" }
    set os_version $tcl_platform(osVersion)
    set os_major [lindex [split $os_version .] 0]
    set os_platform [string tolower $tcl_platform(os)]
    # Remove trailing "Endian"
    set os_endian [string range $tcl_platform(byteOrder) 0 end-6]
    set macosx_version {}
    if {$os_platform == "darwin"} {
        # This will probably break when Apple changes versioning
        set macosx_version [expr 10.0 + ($os_major - 4) / 10.0]
    }

    # Ensure that the macports user directory (i.e. ~/.macports) exists if HOME is defined.
    # Also save $HOME for later use before replacing it with our own.
    if {[info exists env(HOME)]} {
        set macports::user_home $env(HOME)
        set macports::macports_user_dir [file normalize $macports::autoconf::macports_user_dir]
    } elseif {[info exists env(SUDO_USER)] && $os_platform == "darwin"} {
        set macports::user_home [exec dscl -q . -read /Users/$env(SUDO_USER) NFSHomeDirectory | cut -d ' ' -f 2]
        set macports::macports_user_dir [file join ${macports::user_home} [string range $macports::autoconf::macports_user_dir 2 end]]
    } elseif {[exec id -u] != 0 && $os_platform == "darwin"} {
        set macports::user_home [exec dscl -q . -read /Users/[exec id -un] NFSHomeDirectory | cut -d ' ' -f 2]
        set macports::macports_user_dir [file join ${macports::user_home} [string range $macports::autoconf::macports_user_dir 2 end]]
    } else {
        # Otherwise define the user directory as a directory that will never exist
        set macports::macports_user_dir "/dev/null/NO_HOME_DIR"
        set macports::user_home "/dev/null/NO_HOME_DIR"
    }

    # Configure the search path for configuration files
    set conf_files ""
    lappend conf_files "${macports_conf_path}/macports.conf"
    if { [file isdirectory $macports_user_dir] } {
        lappend conf_files "${macports_user_dir}/macports.conf"
    }
    if {[info exists env(PORTSRC)]} {
        set PORTSRC $env(PORTSRC)
        lappend conf_files ${PORTSRC}
    }

    # Process all configuration files we find on conf_files list
    foreach file $conf_files {
        if [file exists $file] {
            set portconf $file
            set fd [open $file r]
            while {[gets $fd line] >= 0} {
                if {[regexp {^(\w+)([ \t]+(.*))?$} $line match option ignore val] == 1} {
                    if {[lsearch $bootstrap_options $option] >= 0} {
                        set macports::$option [string trim $val]
                        global macports::$option
                    }
                }
            }
            close $fd
        }
    }

    # Process per-user only settings
    set per_user "${macports_user_dir}/user.conf"
    if [file exists $per_user] {
        set fd [open $per_user r]
        while {[gets $fd line] >= 0} {
            if {[regexp {^(\w+)([ \t]+(.*))?$} $line match option ignore val] == 1} {
                if {[lsearch $user_options $option] >= 0} {
                    set macports::$option $val
                    global macports::$option
                }
            }
        }
        close $fd
    }

    if {![info exists sources_conf]} {
        return -code error "sources_conf must be set in ${macports_conf_path}/macports.conf or in your ${macports_user_dir}/macports.conf file"
    }
    set fd [open $sources_conf r]
    while {[gets $fd line] >= 0} {
        set line [string trimright $line]
        if {![regexp {^\s*#|^$} $line]} {
            if {[regexp {^([\w-]+://\S+)(?:\s+\[(\w+(?:,\w+)*)\])?$} $line _ url flags]} {
                set flags [split $flags ,]
                foreach flag $flags {
                    if {[lsearch -exact [list nosync default] $flag] == -1} {
                        ui_warn "$sources_conf source '$line' specifies invalid flag '$flag'"
                    }
                    if {$flag == "default"} {
                        if {[info exists sources_default]} {
                            ui_warn "More than one default port source is defined."
                        }
                        set sources_default [concat [list $url] $flags]
                    }
                }
                lappend sources [concat [list $url] $flags]
            } else {
                ui_warn "$sources_conf specifies invalid source '$line', ignored."
            }
        }
    }
    close $fd
    # Make sure the default port source is defined. Otherwise
    # [macports::getportresourcepath] fails when the first source doesn't
    # contain _resources.
    if {![info exists sources_default]} {
        ui_warn "No default port source specified in $sources_conf, using last source as default"
        set sources_default [lindex $sources end]
    }

    if {![info exists sources]} {
        if {[file isdirectory ports]} {
            set sources "file://[pwd]/ports"
        } else {
            return -code error "No sources defined in $sources_conf"
        }
    }

    if {[info exists variants_conf]} {
        if {[file exist $variants_conf]} {
            set fd [open $variants_conf r]
            while {[gets $fd line] >= 0} {
                set line [string trimright $line]
                if {![regexp {^[\ \t]*#.*$|^$} $line]} {
                    foreach arg [split $line " \t"] {
                        if {[regexp {^([-+])([-A-Za-z0-9_+\.]+)$} $arg match sign opt] == 1} {
                            if {![info exists variations($opt)]} {
                                set variations($opt) $sign
                            }
                        } else {
                            ui_warn "$variants_conf specifies invalid variant syntax '$arg', ignored."
                        }
                    }
                }
            }
            close $fd
        } else {
            ui_debug "$variants_conf does not exist, variants_conf setting ignored."
        }
    }
    global macports::global_variations
    array set macports::global_variations [array get variations]

    # pubkeys.conf
    set macports::archivefetch_pubkeys {}
    if {[file isfile [file join ${macports_conf_path} pubkeys.conf]]} {
        set fd [open [file join ${macports_conf_path} pubkeys.conf] r]
        while {[gets $fd line] >= 0} {
            set line [string trim $line]
            if {![regexp {^[\ \t]*#.*$|^$} $line]} {
                lappend macports::archivefetch_pubkeys $line
            }
        }
        close $fd
    } else {
        ui_debug "pubkeys.conf does not exist."
    }

    if {![info exists portdbpath]} {
        return -code error "portdbpath must be set in ${macports_conf_path}/macports.conf or in your ${macports_user_dir}/macports.conf"
    }
    if {![file isdirectory $portdbpath]} {
        if {![file exists $portdbpath]} {
            if {[catch {file mkdir $portdbpath} result]} {
                return -code error "portdbpath $portdbpath does not exist and could not be created: $result"
            }
        } else {
            return -code error "$portdbpath is not a directory. Please create the directory $portdbpath and try again"
        }
    }

    set env(HOME) [file join $portdbpath home]
    set registry.path $portdbpath

    # Format for receipts; currently only "sqlite" is allowed
    # could previously be "flat", so we switch that to sqlite
    if {![info exists portdbformat] || $portdbformat == "flat" || $portdbformat == "sqlite"} {
        set registry.format receipt_sqlite
    } else {
        return -code error "unknown registry format '$portdbformat' set in macports.conf"
    }

    # Autoclean mode, whether to automatically call clean after "install"
    if {![info exists portautoclean]} {
        set macports::portautoclean "yes"
        global macports::portautoclean
    }
	# whether to keep logs after successful builds
   	if {![info exists keeplogs]} {
        set macports::keeplogs "no"
        global macports::keeplogs
    }
   
    # Check command line override for autoclean
    if {[info exists macports::global_options(ports_autoclean)]} {
        if {![string equal $macports::global_options(ports_autoclean) $portautoclean]} {
            set macports::portautoclean $macports::global_options(ports_autoclean)
        }
    }
    # Trace mode, whether to use darwintrace to debug ports.
    if {![info exists porttrace]} {
        set macports::porttrace "no"
        global macports::porttrace
    }
    # Check command line override for trace
    if {[info exists macports::global_options(ports_trace)]} {
        if {![string equal $macports::global_options(ports_trace) $porttrace]} {
            set macports::porttrace $macports::global_options(ports_trace)
        }
    }

    # Duplicate prefix into prefix_frozen, so that port actions
    # can always get to the original prefix, even if a portfile overrides prefix
    set macports::prefix_frozen $prefix

    # Export verbosity.
    if {![info exists portverbose]} {
        set macports::portverbose "no"
        global macports::portverbose
    }
    if {[info exists macports::ui_options(ports_verbose)]} {
        if {![string equal $macports::ui_options(ports_verbose) $portverbose]} {
            set macports::portverbose $macports::ui_options(ports_verbose)
        }
    }

    # Archive type, what type of binary archive to use (CPIO, gzipped
    # CPIO, XAR, etc.)
    global macports::portarchivetype
    if {![info exists portarchivetype]} {
        set macports::portarchivetype "tbz2"
    } else {
        set macports::portarchivetype [lindex $portarchivetype 0]
    }

    # Set rync options
    if {![info exists rsync_server]} {
        set macports::rsync_server rsync.macports.org
        global macports::rsync_server
    }
    if {![info exists rsync_dir]} {
        set macports::rsync_dir release/tarballs/base.tar
        global macports::rsync_dir
    }
    if {![info exists rsync_options]} {
        set rsync_options "-rtzv --delete-after"
        global macports::rsync_options
    }

    set portsharepath ${prefix}/share/macports
    if {![file isdirectory $portsharepath]} {
        return -code error "Data files directory '$portsharepath' must exist"
    }

    if {![info exists libpath]} {
        set libpath "${prefix}/share/macports/Tcl"
    }

    if {![info exists binpath]} {
        set env(PATH) "${prefix}/bin:${prefix}/sbin:/bin:/sbin:/usr/bin:/usr/sbin"
    } else {
        set env(PATH) "$binpath"
    }

    # Set startupitem default type (can be overridden by portfile)
    if {![info exists macports::startupitem_type]} {
        set macports::startupitem_type "default"
    }

    # Default place_worksymlink
    if {![info exists macports::place_worksymlink]} {
        set macports::place_worksymlink yes
    }

    # Default mp remote options
    if {![info exists macports::mp_remote_url]} {
        set macports::mp_remote_url "http://db.macports.org"
    }
    if {![info exists macports::mp_remote_submit_url]} {
        set macports::mp_remote_submit_url "${macports::mp_remote_url}/submit"
    }

    # Default mp configure options
    if {![info exists macports::configureccache]} {
        set macports::configureccache no
    }
    if {![info exists macports::ccache_dir]} {
        set macports::ccache_dir [file join $portdbpath build .ccache]
    }
    if {![info exists macports::ccache_size]} {
        set macports::ccache_size "2G"
    }
    if {![info exists macports::configuredistcc]} {
        set macports::configuredistcc no
    }
    if {![info exists macports::configurepipe]} {
        set macports::configurepipe yes
    }

    # Default mp build options
    if {![info exists macports::buildnicevalue]} {
        set macports::buildnicevalue 0
    }
    if {![info exists macports::buildmakejobs]} {
        set macports::buildmakejobs 0
    }

    # default user to run as when privileges can be dropped
    if {![info exists macports::macportsuser]} {
        set macports::macportsuser $macports::autoconf::macportsuser
    }

    # Default mp universal options
    if {![info exists macports::universal_archs]} {
        if {$os_major >= 10} {
            set macports::universal_archs {x86_64 i386}
        } else {
            set macports::universal_archs {i386 ppc}
        }
    } elseif {[llength $macports::universal_archs] < 2} {
        ui_warn "invalid universal_archs configured (should contain at least 2 archs)"
    }
    
    # Default arch to build for
    if {![info exists macports::build_arch]} {
        if {$os_platform == "darwin"} {
            if {$os_major >= 10} {
                if {[sysctl hw.cpu64bit_capable] == 1} {
                    set macports::build_arch x86_64
                } else {
                    set macports::build_arch i386
                }
            } else {
                if {$os_arch == "powerpc"} {
                    set macports::build_arch ppc
                } else {
                    set macports::build_arch i386
                }
            }
        } else {
            set macports::build_arch ""
        }
    } else {
        set macports::build_arch [lindex $macports::build_arch 0]
    }

    if {![info exists macports::macosx_deployment_target]} {
        set macports::macosx_deployment_target $macosx_version
    }

    # make tools we run operate in UTF-8 mode
    set env(LANG) en_US.UTF-8

    # ENV cleanup.
    set keepenvkeys {
        DISPLAY DYLD_FALLBACK_FRAMEWORK_PATH
        DYLD_FALLBACK_LIBRARY_PATH DYLD_FRAMEWORK_PATH
        DYLD_LIBRARY_PATH DYLD_INSERT_LIBRARIES
        HOME JAVA_HOME MASTER_SITE_LOCAL ARCHIVE_SITE_LOCAL
        PATCH_SITE_LOCAL PATH PORTSRC RSYNC_PROXY
        USER GROUP LANG
        http_proxy HTTPS_PROXY FTP_PROXY ALL_PROXY NO_PROXY
        COLUMNS LINES
    }
    if {[info exists extra_env]} {
        set keepenvkeys [concat ${keepenvkeys} ${extra_env}]
    }

    if {[file isdirectory $libpath]} {
        lappend auto_path $libpath
        set macports::auto_path $auto_path

        # XXX: not sure if this the best place, but it needs to happen
        # early, and after auto_path has been set.  Or maybe Pextlib
        # should ship with macports1.0 API?
        package require Pextlib 1.0
        package require registry 1.0
        package require registry2 2.0
    } else {
        return -code error "Library directory '$libpath' must exist"
    }

    # don't keep unusable TMPDIR/TMP values
    foreach var {TMP TMPDIR} {
        if {[info exists env($var)] && [file writable $env($var)] && 
            ([getuid] != 0 || $macportsuser == "root" ||
             [file attributes $env($var) -owner] == $macportsuser)} {
            lappend keepenvkeys $var
        }
    }

    set env_names [array names env]
    foreach envkey $env_names {
        if {[lsearch -exact $keepenvkeys $envkey] == -1} {
            unset env($envkey)
        }
    }

    # unset environment an extra time, to work around bugs in Leopard Tcl
    if {$macosx_version == "10.5"} {
        foreach envkey $env_names {
            if {[lsearch -exact $keepenvkeys $envkey] == -1} {
                unsetenv $envkey
            }
        }
    }

    if {![info exists xcodeversion] || ![info exists xcodebuildcmd]} {
        # We'll resolve these later (if needed)
        trace add variable macports::xcodeversion read macports::setxcodeinfo
        trace add variable macports::xcodebuildcmd read macports::setxcodeinfo
    }

    if {[getuid] == 0 && $os_major >= 11 && $os_platform == "darwin" && [vercmp $xcodeversion 4.3] >= 0} {
        macports::copy_xcode_plist $env(HOME)
    }

    # Set the default umask
    if {![info exists destroot_umask]} {
        set destroot_umask 022
    }

    if {[info exists master_site_local] && ![info exists env(MASTER_SITE_LOCAL)]} {
        set env(MASTER_SITE_LOCAL) "$master_site_local"
    }
    if {[info exists patch_site_local] && ![info exists env(PATCH_SITE_LOCAL)]} {
        set env(PATCH_SITE_LOCAL) "$patch_site_local"
    }
    if {[info exists archive_site_local] && ![info exists env(ARCHIVE_SITE_LOCAL)]} {
        set env(ARCHIVE_SITE_LOCAL) "$archive_site_local"
    }

    # Proxy handling (done this late since Pextlib is needed)
    if {![info exists proxy_override_env] } {
        set proxy_override_env "no"
    }
    if {[catch {array set sysConfProxies [get_systemconfiguration_proxies]} result]} {
        return -code error "Unable to get proxy configuration from system: $result"
    }
    if {![info exists env(http_proxy)] || $proxy_override_env == "yes" } {
        if {[info exists proxy_http]} {
            set env(http_proxy) $proxy_http
        } elseif {[info exists sysConfProxies(proxy_http)]} {
            set env(http_proxy) $sysConfProxies(proxy_http)
        }
    }
    if {![info exists env(HTTPS_PROXY)] || $proxy_override_env == "yes" } {
        if {[info exists proxy_https]} {
            set env(HTTPS_PROXY) $proxy_https
        } elseif {[info exists sysConfProxies(proxy_https)]} {
            set env(HTTPS_PROXY) $sysConfProxies(proxy_https)
        }
    }
    if {![info exists env(FTP_PROXY)] || $proxy_override_env == "yes" } {
        if {[info exists proxy_ftp]} {
            set env(FTP_PROXY) $proxy_ftp
        } elseif {[info exists sysConfProxies(proxy_ftp)]} {
            set env(FTP_PROXY) $sysConfProxies(proxy_ftp)
        }
    }
    if {![info exists env(RSYNC_PROXY)] || $proxy_override_env == "yes" } {
        if {[info exists proxy_rsync]} {
            set env(RSYNC_PROXY) $proxy_rsync
        }
    }
    if {![info exists env(NO_PROXY)] || $proxy_override_env == "yes" } {
        if {[info exists proxy_skip]} {
            set env(NO_PROXY) $proxy_skip
        } elseif {[info exists sysConfProxies(proxy_skip)]} {
            set env(NO_PROXY) $sysConfProxies(proxy_skip)
        }
    }

    # add ccache to environment
    set env(CCACHE_DIR) ${macports::ccache_dir}

    # load the quick index
    _mports_load_quickindex

    if {![info exists macports::ui_options(ports_no_old_index_warning)]} {
        set default_source_url [lindex ${sources_default} 0]
        if {[macports::getprotocol $default_source_url] == "file" || [macports::getprotocol $default_source_url] == "rsync"} {
            set default_portindex [macports::getindex $default_source_url]
            if {[file exists $default_portindex] && [expr [clock seconds] - [file mtime $default_portindex]] > 1209600} {
                ui_warn "port definitions are more than two weeks old, consider using selfupdate"
            }
        }
    }

    # init registry
    set db_path [file join ${registry.path} registry registry.db]
    set db_exists [file exists $db_path]
    registry::open $db_path
    # for the benefit of the portimage code that is called from multiple interpreters
    global registry_open
    set registry_open yes
    # convert any flat receipts if we just created a new db
    if {$db_exists == 0 && [file writable $db_path]} {
        ui_warn "Converting your registry to sqlite format, this might take a while..."
        if {[catch {registry::convert_to_sqlite}]} {
            ui_debug "$::errorInfo"
            file delete -force $db_path
            error "Failed to convert your registry to sqlite!"
        } else {
            ui_warn "Successfully converted your registry to sqlite!"
        }
    }
}

# call this just before you exit
proc mportshutdown {} {
    # close it down so the cleanup stuff is called, e.g. vacuuming the db
    registry::close
}

# link plist for xcode 4.3's benefit
proc macports::copy_xcode_plist {target_homedir} {
    global macports::user_home macports::macportsuser
    set user_plist "${user_home}/Library/Preferences/com.apple.dt.Xcode.plist"
    set target_dir "${target_homedir}/Library/Preferences"
    file delete -force "${target_dir}/com.apple.dt.Xcode.plist"
    if {[file isfile $user_plist]} {
        if {![file isdirectory "${target_dir}"]} {
            if {[catch {file mkdir "${target_dir}"} result]} {
                ui_warn "Failed to create Library/Preferences in ${target_homedir}: $result"
                return
            }
        }
        if {[file writable ${target_dir}] && [catch {
            ui_debug "Copying $user_plist to ${target_dir}"
            file copy -force $user_plist $target_dir
            file attributes "${target_dir}/com.apple.dt.Xcode.plist" -owner $macportsuser -permissions 0644
        } result]} {
            ui_warn "Failed to copy com.apple.dt.Xcode.plist to ${target_dir}: $result"
        }
    }
}

proc macports::worker_init {workername portpath porturl portbuildpath options variations} {
    global macports::portinterp_options macports::portinterp_deferred_options

    # Hide any Tcl commands that should be inaccessible to port1.0 and Portfiles
    # exit: It should not be possible to exit the interpreter
    interp hide $workername exit

    # cd: This is necessary for some code in port1.0, but should be hidden
    interp eval $workername "rename cd _cd"

    # Tell the sub interpreter about all the Tcl packages we already
    # know about so it won't glob for packages.
    foreach pkgName [package names] {
        foreach pkgVers [package versions $pkgName] {
            set pkgLoadScript [package ifneeded $pkgName $pkgVers]
            $workername eval "package ifneeded $pkgName $pkgVers {$pkgLoadScript}"
        }
    }

    # Create package require abstraction procedure
    $workername eval "proc PortSystem \{version\} \{ \n\
            package require port \$version \}"

    # Clearly separate slave interpreters and the master interpreter.
    $workername alias mport_exec mportexec
    $workername alias mport_open mportopen
    $workername alias mport_close mportclose
    $workername alias mport_lookup mportlookup
    $workername alias mport_info mportinfo
    $workername alias set_phase set_phase

    # instantiate the UI call-backs
    foreach priority ${macports::ui_priorities} {
        $workername alias ui_$priority ui_$priority
        foreach phase ${macports::port_phases} {
            $workername alias ui_${priority}_${phase} ui_${priority}_${phase}
        }
 
    }

    $workername alias ui_prefix ui_prefix
    $workername alias ui_channels ui_channels
    
    $workername alias ui_warn_once ui_warn_once

    # Export some utility functions defined here.
    $workername alias macports_create_thread macports::create_thread
    $workername alias getportworkpath_from_buildpath macports::getportworkpath_from_buildpath
    $workername alias getportresourcepath macports::getportresourcepath
    $workername alias getportlogpath macports::getportlogpath
    $workername alias getdefaultportresourcepath macports::getdefaultportresourcepath
    $workername alias getprotocol macports::getprotocol
    $workername alias getportdir macports::getportdir
    $workername alias findBinary macports::findBinary
    $workername alias binaryInPath macports::binaryInPath
    $workername alias sysctl sysctl
    $workername alias realpath realpath
    $workername alias _mportsearchpath _mportsearchpath
    $workername alias _portnameactive _portnameactive

    # New Registry/Receipts stuff
    $workername alias registry_new registry::new_entry
    $workername alias registry_open registry::open_entry
    $workername alias registry_write registry::write_entry
    $workername alias registry_prop_store registry::property_store
    $workername alias registry_prop_retr registry::property_retrieve
    $workername alias registry_exists registry::entry_exists
    $workername alias registry_exists_for_name registry::entry_exists_for_name
    $workername alias registry_activate portimage::activate
    $workername alias registry_deactivate portimage::deactivate
    $workername alias registry_deactivate_composite portimage::deactivate_composite
    $workername alias registry_uninstall registry_uninstall::uninstall
    $workername alias registry_register_deps registry::register_dependencies
    $workername alias registry_fileinfo_for_index registry::fileinfo_for_index
    $workername alias registry_fileinfo_for_file registry::fileinfo_for_file
    $workername alias registry_bulk_register_files registry::register_bulk_files
    $workername alias registry_active registry::active
    $workername alias registry_file_registered registry::file_registered
    $workername alias registry_port_registered registry::port_registered

    # deferred options processing.
    $workername alias getoption macports::getoption

    foreach opt $portinterp_options {
        if {![info exists $opt]} {
            global macports::$opt
        }
        if {[info exists $opt]} {
            $workername eval set system_options($opt) \{[set $opt]\}
            $workername eval set $opt \{[set $opt]\}
        }
    }

    foreach opt $portinterp_deferred_options {
        global macports::$opt
        # define the trace hook.
        $workername eval \
            "proc trace_$opt {name1 name2 op} { \n\
                trace remove variable ::$opt read ::trace_$opt \n\
                global $opt \n\
                set $opt \[getoption $opt\] \n\
            }"
        # next access will actually define the variable.
        $workername eval "trace add variable ::$opt read ::trace_$opt"
        # define some value now
        $workername eval set $opt "?"
    }

    foreach {opt val} $options {
        $workername eval set user_options($opt) $val
        $workername eval set $opt $val
    }

    foreach {var val} $variations {
        $workername eval set variations($var) $val
    }
}

# Create a thread with most configuration options set.
# The newly created thread is sent portinterp_options vars and knows where to
# find all packages we know.
proc macports::create_thread {} {
    package require Thread

    global macports::portinterp_options

    # Create the thread.
    set result [thread::create -preserved {thread::wait}]

    # Tell the thread about all the Tcl packages we already
    # know about so it won't glob for packages.
    foreach pkgName [package names] {
        foreach pkgVers [package versions $pkgName] {
            set pkgLoadScript [package ifneeded $pkgName $pkgVers]
            thread::send -async $result "package ifneeded $pkgName $pkgVers {$pkgLoadScript}"
        }
    }

    # inherit configuration variables.
    thread::send -async $result "namespace eval macports {}"
    foreach opt $portinterp_options {
        if {![info exists $opt]} {
            global macports::$opt
        }
        if {[info exists $opt]} {
            thread::send -async $result "global macports::$opt"
            set val [set macports::$opt]
            thread::send -async $result "set macports::$opt \"$val\""
        }
    }

    return $result
}

proc macports::get_tar_flags {suffix} {
    switch -- $suffix {
        .tbz -
        .tbz2 {
            return "-j"
        }
        .tgz {
            return "-z"
        }
        .txz {
            return "--use-compress-program [findBinary xz {}] -"
        }
        .tlz {
            return "--use-compress-program [findBinary lzma {}] -"
        }
        default {
            return "-"
        }
    }
}

proc macports::fetch_port {url {local 0}} {
    global macports::portdbpath
    set fetchdir [file join $portdbpath portdirs]
    file mkdir $fetchdir
    if {![file writable $fetchdir]} {
        return -code error "Port remote fetch failed: You do not have permission to write to $fetchdir"
    }
    if {$local} {
        set fetchfile $url
    } else {
        set fetchfile [file tail $url]
        if {[catch {curl fetch $url [file join $fetchdir $fetchfile]} result]} {
            return -code error "Port remote fetch failed: $result"
        }
    }
    set oldpwd [pwd]
    cd $fetchdir
    # check if this is a binary archive or just the port dir
    set tarcmd [findBinary tar $macports::autoconf::tar_path]
    set tarflags [get_tar_flags [file extension $fetchfile]]
    set qflag ${macports::autoconf::tar_q}
    set cmdline "$tarcmd ${tarflags}${qflag}xOf \"$fetchfile\" +CONTENTS"
    ui_debug "$cmdline"
    if {![catch {set contents [eval exec $cmdline]}]} {
        set binary 1
        ui_debug "getting port name from binary archive"
        # get the portname from the contents file
        foreach line [split $contents "\n"] {
            if {[lindex $line 0] == "@name"} {
                # actually ${name}-${version}_${revision}
                set portname [lindex $line 1]
            }
        }
        ui_debug "port name is '$portname'"
        file mkdir $portname
        cd $portname
    } else {
        set binary 0
        set portname [file rootname $fetchfile]
    }

    # extract the portfile (and possibly files dir if not a binary archive)
    ui_debug "extracting port archive to [pwd]"
    if {$binary} {
        set cmdline "$tarcmd ${tarflags}${qflag}xOf \"$fetchfile\" +PORTFILE > Portfile"
    } else {
        set cmdline "$tarcmd ${tarflags}xf \"$fetchfile\""
    }
    ui_debug "$cmdline"
    if {[catch {eval exec $cmdline} result]} {
        return -code error "Port extract failed: $result"
    }

    cd $oldpwd
    return [file join $fetchdir $portname]
}

proc macports::getprotocol {url} {
    if {[regexp {(?x)([^:]+)://.+} $url match protocol] == 1} {
        return ${protocol}
    } else {
        return -code error "Can't parse url $url"
    }
}

# XXX: this really needs to be rethought in light of the remote index
# I've added the destdir parameter.  This is the location a remotely
# fetched port will be downloaded to (currently only applies to
# mports:// sources).
proc macports::getportdir {url {destdir "."}} {
    global macports::extracted_portdirs
    set protocol [macports::getprotocol $url]
    switch ${protocol} {
        file {
            set path [file normalize [string range $url [expr [string length $protocol] + 3] end]]
            if {[file isdirectory $path]} {
                return $path
            } else {
                # need to create a local dir for the exracted port, but only once
                if {![info exists macports::extracted_portdirs($url)]} {
                    set macports::extracted_portdirs($url) [macports::fetch_port $path 1]
                }
                return $macports::extracted_portdirs($url)
            }
        }
        mports {
            return [macports::index::fetch_port $url $destdir]
        }
        https -
        http -
        ftp {
            if {![info exists macports::extracted_portdirs($url)]} {
                set macports::extracted_portdirs($url) [macports::fetch_port $url 0]
            }
            return $macports::extracted_portdirs($url)
        }
        default {
            return -code error "Unsupported protocol $protocol"
        }
    }
}

##
# Get the path to the _resources directory of the source
#
# If the file is not available in the current source, it will fall back to the
# default source. This behavior is controlled by the fallback parameter.
#
# @param url port url
# @param path path in _resources we are interested in
# @param fallback fall back to the default source tree
# @return path to the _resources directory or the path to the fallback
proc macports::getportresourcepath {url {path ""} {fallback yes}} {
    global macports::sources_default

    set protocol [getprotocol $url]

    switch -- ${protocol} {
        file {
            set proposedpath [file normalize [file join [getportdir $url] .. ..]]
        }
        default {
            set proposedpath [getsourcepath $url]
        }
    }

    # append requested path
    set proposedpath [file join $proposedpath _resources $path]

    if {$fallback == "yes" && ![file exists $proposedpath]} {
        return [getdefaultportresourcepath $path]
    }

    return $proposedpath
}

##
# Get the path to the _resources directory of the default source
#
# @param path path in _resources we are interested in
# @return path to the _resources directory of the default source
proc macports::getdefaultportresourcepath {{path ""}} {
    global macports::sources_default

    set default_source_url [lindex ${sources_default} 0]
    if {[getprotocol $default_source_url] == "file"} {
        set proposedpath [getportdir $default_source_url]
    } else {
        set proposedpath [getsourcepath $default_source_url]
    }

    # append requested path
    set proposedpath [file join $proposedpath _resources $path]

    return $proposedpath
}


# mportopen
# Opens a MacPorts portfile specified by a URL.  The Portfile is
# opened with the given list of options and variations.  The result
# of this function should be treated as an opaque handle to a
# MacPorts Portfile.

proc mportopen {porturl {options ""} {variations ""} {nocache ""}} {
    global macports::portdbpath macports::portconf macports::open_mports auto_path

    # Look for an already-open MPort with the same URL.
    # if found, return the existing reference and bump the refcount.
    if {$nocache != ""} {
        set mport {}
    } else {
        set mport [dlist_match_multi $macports::open_mports [list porturl $porturl variations $variations options $options]]
    }
    if {$mport != {}} {
        # just in case more than one somehow matches
        set mport [lindex $mport 0]
        set refcnt [ditem_key $mport refcnt]
        incr refcnt
        ditem_key $mport refcnt $refcnt
        return $mport
    }

    array set options_array $options
    if {[info exists options_array(portdir)]} {
        set portdir $options_array(portdir)
    } else {
        set portdir ""
    }

    set portpath [macports::getportdir $porturl $portdir]
    ui_debug "Changing to port directory: $portpath"
    cd $portpath
    if {![file isfile Portfile]} {
        return -code error "Could not find Portfile in $portpath"
    }

    set workername [interp create]

    set mport [ditem_create]
    lappend macports::open_mports $mport
    ditem_key $mport porturl $porturl
    ditem_key $mport portpath $portpath
    ditem_key $mport workername $workername
    ditem_key $mport options $options
    ditem_key $mport variations $variations
    ditem_key $mport refcnt 1

    macports::worker_init $workername $portpath $porturl [macports::getportbuildpath $portpath] $options $variations

    $workername eval source Portfile

    # add the default universal variant if appropriate, and set up flags that
    # are conditional on whether universal is set
    $workername eval universal_setup

    # evaluate the variants
    if {[$workername eval eval_variants variations] != 0} {
        mportclose $mport
        error "Error evaluating variants"
    }

    ditem_key $mport provides [$workername eval return \$subport]

    return $mport
}

# mportopen_installed
# opens a portfile stored in the registry
proc mportopen_installed {name version revision variants options} {
    global macports::registry.path
    set regref [lindex [registry::entry imaged $name $version $revision $variants] 0]
    set portfile_dir [file join ${registry.path} registry portfiles $name "${version}_${revision}${variants}"]
    file mkdir $portfile_dir
    set fd [open "${portfile_dir}/Portfile" w]
    puts $fd [$regref portfile]
    close $fd
    file mtime "${portfile_dir}/Portfile" [$regref date]

    set variations {}
    set minusvariant [lrange [split [$regref negated_variants] -] 1 end]
    set plusvariant [lrange [split [$regref variants] +] 1 end]
    foreach v $plusvariant {
        lappend variations $v "+"
    }
    foreach v $minusvariant {
        lappend variations $v "-"
    }
    lappend options subport $name
    return [mportopen "file://${portfile_dir}/" $options $variations]
}

# mportclose_installed
# close mport opened with mportopen_installed and clean up associated files
proc mportclose_installed {mport} {
    global macports::registry.path
    foreach key {subport version revision portvariants} {
        set $key [_mportkey $mport $key]
    }
    mportclose $mport
    set portfiles_dir [file join ${registry.path} registry portfiles $subport]
    set portfile [file join $portfiles_dir "${version}_${revision}${portvariants}" Portfile]
    file delete -force $portfile [file dirname $portfile]
    if {[llength [glob -nocomplain -directory $portfiles_dir *]] == 0} {
        file delete -force $portfiles_dir
    }
}

# Traverse a directory with ports, calling a function on the path of ports
# (at the second depth).
# I.e. the structure of dir shall be:
# category/port/
# with a Portfile file in category/port/
#
# func:     function to call on every port directory (it is passed
#           category/port/ as its parameter)
# root:     the directory with all the categories directories.
proc mporttraverse {func {root .}} {
    # Save the current directory
    set pwd [pwd]

    # Join the root.
    set pathToRoot [file join $pwd $root]

    # Go to root because some callers expects us to be there.
    cd $pathToRoot

    foreach category [lsort -increasing -unique [readdir $root]] {
        set pathToCategory [file join $root $category]
        # process the category dirs but not _resources
        if {[file isdirectory $pathToCategory] && [string index [file tail $pathToCategory] 0] != "_"} {
            # Iterate on port directories.
            foreach port [lsort -increasing -unique [readdir $pathToCategory]] {
                set pathToPort [file join $pathToCategory $port]
                if {[file isdirectory $pathToPort] &&
                  [file exists [file join $pathToPort "Portfile"]]} {
                    # Call the function.
                    $func [file join $category $port]

                    # Restore the current directory because some
                    # functions changes it.
                    cd $pathToRoot
                }
            }
        }
    }

    # Restore the current directory.
    cd $pwd
}

### _mportsearchpath is private; subject to change without notice

# depregex -> regex on the filename to find.
# search_path -> directories to search
# executable -> whether we want to check that the file is executable by current
#               user or not.
proc _mportsearchpath {depregex search_path {executable 0} {return_match 0}} {
    set found 0
    foreach path $search_path {
        if {![file isdirectory $path]} {
            continue
        }

        if {[catch {set filelist [readdir $path]} result]} {
            return -code error "$result ($path)"
        }

        foreach filename $filelist {
            if {[regexp $depregex $filename] &&
              (($executable == 0) || [file executable [file join $path $filename]])} {
                ui_debug "Found Dependency: path: $path filename: $filename regex: $depregex"
                set found 1
                break
            }
        }
    }
    if {$return_match} {
        if {$found} {
            return [file join $path $filename]
        } else {
            return ""
        }
    } else {
        return $found
    }
}


### _mportinstalled is private; may change without notice

# Determine if a port is already *installed*, as in "in the registry".
proc _mportinstalled {mport} {
    # Check for the presence of the port in the registry
    set workername [ditem_key $mport workername]
    return [$workername eval registry_exists_for_name \${subport}]
}

# Determine if a port is active
proc _mportactive {mport} {
    set workername [ditem_key $mport workername]
    if {![catch {set reslist [$workername eval registry_active \${subport}]}] && [llength $reslist] > 0} {
        set i [lindex $reslist 0]
        set name [lindex $i 0]
        set version [lindex $i 1]
        set revision [lindex $i 2]
        set variants [lindex $i 3]
        array set portinfo [mportinfo $mport]
        if {$name == $portinfo(name) && $version == $portinfo(version)
            && $revision == $portinfo(revision) && $variants == $portinfo(canonical_active_variants)} {
            return 1
        }
    }
    return 0
}

# Determine if the named port is active
proc _portnameactive {portname} {
    if {[catch {set reslist [registry::active $portname]}]} {
        return 0
    } else {
        return [expr [llength $reslist] > 0]
    }
}

### _mportispresent is private; may change without notice

# Determine if some depspec is satisfied or if the given port is installed
# and active.
# We actually start with the registry (faster?)
#
# mport     the port declaring the dep (context in which to evaluate $prefix etc)
# depspec   the dependency test specification (path, bin, lib, etc.)
proc _mportispresent {mport depspec} {
    set portname [lindex [split $depspec :] end]
    ui_debug "Searching for dependency: $portname"
    set res [_portnameactive $portname]
    if {$res != 0} {
        ui_debug "Found Dependency: receipt exists for $portname"
        return 1
    } else {
        # The receipt test failed, use one of the depspec regex mechanisms
        ui_debug "Didn't find receipt, going to depspec regex for: $portname"
        set workername [ditem_key $mport workername]
        set type [lindex [split $depspec :] 0]
        switch $type {
            lib { return [$workername eval _libtest $depspec] }
            bin { return [$workername eval _bintest $depspec] }
            path { return [$workername eval _pathtest $depspec] }
            port { return 0 }
            default {return -code error "unknown depspec type: $type"}
        }
        return 0
    }
}

### _mportconflictsinstalled is private; may change without notice

# Determine if the port, per the conflicts option, has any conflicts with
# what is installed.
#
# mport   the port to check for conflicts
# Returns a list of which installed ports conflict, or an empty list if none
proc _mportconflictsinstalled {mport conflictinfo} {
    set conflictlist {}
    if {[llength $conflictinfo] > 0} {
        ui_debug "Checking for conflicts against [_mportkey $mport subport]"
        foreach conflictport ${conflictinfo} {
            if {[_mportispresent $mport port:${conflictport}]} {
                lappend conflictlist $conflictport
            }
        }
    } else {
        ui_debug "[_mportkey $mport subport] has no conflicts"
    }

    return $conflictlist
}


### _mportexec is private; may change without notice

proc _mportexec {target mport} {
    set portname [_mportkey $mport subport]
    macports::push_log $mport
    # xxx: set the work path?
    set workername [ditem_key $mport workername]
    $workername eval validate_macportsuser
    if {![catch {$workername eval check_variants $target} result] && $result == 0 &&
        ![catch {$workername eval check_supported_archs} result] && $result == 0 &&
        ![catch {$workername eval eval_targets $target} result] && $result == 0} {
        # If auto-clean mode, clean-up after dependency install
        if {[string equal ${macports::portautoclean} "yes"]} {
            # Make sure we are back in the port path before clean
            # otherwise if the current directory had been changed to
            # inside the port,  the next port may fail when trying to
            # install because [pwd] will return a "no file or directory"
            # error since the directory it was in is now gone.
            set portpath [ditem_key $mport portpath]
            catch {cd $portpath}
            $workername eval eval_targets clean
        }
        # XXX hack to avoid running out of fds due to sqlite temp files, ticket #24857
        interp delete $workername
        macports::pop_log
        return 0
    } else {
        # An error occurred.
        global ::logenabled ::debuglogname
        ui_error "Failed to install $portname"
        ui_debug "$::errorInfo"
        if {[info exists ::logenabled] && $::logenabled && [info exists ::debuglogname]} {
            ui_notice "Log for $portname is at: $::debuglogname"
        }
        macports::pop_log
        return 1
    }
}

# mportexec
# Execute the specified target of the given mport.
proc mportexec {mport target} {
    set workername [ditem_key $mport workername]

    # check for existence of macportsuser and use fallback if necessary
    $workername eval validate_macportsuser
    # check variants
    if {[$workername eval check_variants $target] != 0} {
        return 1
    }
    set portname [_mportkey $mport subport]
    if {$target != "clean"} {
        macports::push_log $mport
    }

    # Use _target_needs_deps as a proxy for whether we're going to
    # build and will therefore need to check Xcode version and
    # supported_archs.
    if {[macports::_target_needs_deps $target]} {
        # possibly warn or error out depending on how old xcode is
        if {[$workername eval _check_xcode_version] != 0} {
            return 1
        }
        # error out if selected arch(s) not supported by this port
        if {[$workername eval check_supported_archs] != 0} {
            return 1
        }
    }

    # Before we build the port, we must build its dependencies.
    set dlist {}
    if {[macports::_target_needs_deps $target] && [macports::_mport_has_deptypes $mport [macports::_deptypes_for_target $target $workername]]} {
        registry::exclusive_lock
        # see if we actually need to build this port
        if {($target != "activate" && $target != "install") ||
            ![$workername eval registry_exists \$subport \$version \$revision \$portvariants]} {
    
            # upgrade dependencies that are already installed
            if {![macports::global_option_isset ports_nodeps]} {
                macports::_upgrade_mport_deps $mport $target
            }
        }

        ui_msg -nonewline "--->  Computing dependencies for [_mportkey $mport subport]"
        if {[macports::ui_isset ports_debug]} {
            # play nice with debug messages
            ui_msg ""
        }
        if {[mportdepends $mport $target] != 0} {
            return 1
        }
        if {![macports::ui_isset ports_debug]} {
            ui_msg ""
        }

        # Select out the dependents along the critical path,
        # but exclude this mport, we might not be installing it.
        set dlist [dlist_append_dependents $macports::open_mports $mport {}]

        dlist_delete dlist $mport
        
        # print the dep list
        if {[llength $dlist] > 0} {
            set depstring "--->  Dependencies to be installed:"
            foreach ditem $dlist {
                append depstring " [ditem_key $ditem provides]"
            }
            ui_msg $depstring
        }

        # install them
        set result [dlist_eval $dlist _mportactive [list _mportexec "activate"]]

        registry::exclusive_unlock

        if {$result != {}} {
            set errstring "The following dependencies were not installed:"
            foreach ditem $result {
                append errstring " [ditem_key $ditem provides]"
            }
            ui_error $errstring
            foreach ditem $dlist {
                catch {mportclose $ditem}
            }
            return 1
        }

        # Close the dependencies, we're done installing them.
        foreach ditem $dlist {
            mportclose $ditem
        }
    }

    set clean 0
    if {[string equal ${macports::portautoclean} "yes"] && ([string equal $target "install"] || [string equal $target "activate"])} {
        # If we're doing an install, check if we should clean after
        set clean 1
    }

    # Build this port with the specified target
    set result [$workername eval eval_targets $target]

    # If auto-clean mode and successful install, clean-up after install
    if {$result == 0 && $clean == 1} {
        # Make sure we are back in the port path, just in case
        set portpath [ditem_key $mport portpath]
        catch {cd $portpath}
        $workername eval eval_targets clean
    }
    
    global ::logenabled ::debuglogname
    if {[info exists ::logenabled] && $::logenabled && [info exists ::debuglogname]} {
        if {$result != 0} {
            ui_notice "Log for $portname is at: $::debuglogname"
        }
        macports::pop_log
    }

    return $result
}

# upgrade any dependencies of mport that are installed and needed for target
proc macports::_upgrade_mport_deps {mport target} {
    set options [ditem_key $mport options]
    set workername [ditem_key $mport workername]
    set deptypes [macports::_deptypes_for_target $target $workername]
    array set portinfo [mportinfo $mport]
    array set depscache {}

    set required_archs [$workername eval get_canonical_archs]
    set depends_skip_archcheck [_mportkey $mport depends_skip_archcheck]

    set test _portnameactive

    foreach deptype $deptypes {
        if {![info exists portinfo($deptype)]} {
            set portinfo($deptype) ""
        }
        foreach depspec $portinfo($deptype) {
            set dep_portname [$workername eval _get_dep_port $depspec]
            if {$dep_portname != "" && ![info exists depscache(port:$dep_portname)] && [$test $dep_portname]} {
                set variants {}
    
                # check that the dep has the required archs
                set active_archs [_get_registry_archs $dep_portname]
                if {$deptype != "depends_fetch" && $deptype != "depends_extract"
                    && $active_archs != "" && $active_archs != "noarch" && $required_archs != "noarch"
                    && [lsearch -exact $depends_skip_archcheck $dep_portname] == -1} {
                    set missing {}
                    foreach arch $required_archs {
                        if {[lsearch -exact $active_archs $arch] == -1} {
                            lappend missing $arch
                        }
                    }
                    if {[llength $missing] > 0} {
                        set res [mportlookup $dep_portname]
                        array unset dep_portinfo
                        array set dep_portinfo [lindex $res 1]
                        if {[info exists dep_portinfo(installs_libs)] && !$dep_portinfo(installs_libs)} {
                            set missing {}
                        }
                    }
                    if {[llength $missing] > 0} {
                        if {[info exists dep_portinfo(variants)] && [lsearch $dep_portinfo(variants) universal] != -1} {
                            # dep offers a universal variant
                            if {[llength $active_archs] == 1} {
                                # not installed universal
                                set missing {}
                                foreach arch $required_archs {
                                    if {[lsearch -exact $macports::universal_archs $arch] == -1} {
                                        lappend missing $arch
                                    }
                                }
                                if {[llength $missing] > 0} {
                                    ui_error "Cannot install [_mportkey $mport subport] for the arch(s) '$required_archs' because"
                                    ui_error "its dependency $dep_portname is only installed for the arch '$active_archs'"
                                    ui_error "and the configured universal_archs '$macports::universal_archs' are not sufficient."
                                    return -code error "architecture mismatch"
                                } else {
                                    # upgrade the dep with +universal
                                    lappend variants universal +
                                    lappend options ports_upgrade_enforce-variants yes
                                    ui_debug "enforcing +universal upgrade for $dep_portname"
                                }
                            } else {
                                # already universal
                                ui_error "Cannot install [_mportkey $mport subport] for the arch(s) '$required_archs' because"
                                ui_error "its dependency $dep_portname is only installed for the archs '$active_archs'."
                                return -code error "architecture mismatch"
                            }
                        } else {
                            ui_error "Cannot install [_mportkey $mport subport] for the arch(s) '$required_archs' because"
                            ui_error "its dependency $dep_portname is only installed for the arch '$active_archs'"
                            ui_error "and does not have a universal variant."
                            return -code error "architecture mismatch"
                        }
                    }
                }
    
                set status [macports::upgrade $dep_portname "port:$dep_portname" $variants $options depscache]
                # status 2 means the port was not found in the index
                if {$status != 0 && $status != 2 && ![macports::ui_isset ports_processall]} {
                    return -code error "upgrade $dep_portname failed"
                }
            }
        }
    }
}

# get the archs with which the active version of portname is installed
proc macports::_get_registry_archs {portname} {
    set ilist [registry::active $portname]
    set i [lindex $ilist 0]
    set regref [registry::open_entry [lindex $i 0] [lindex $i 1] [lindex $i 2] [lindex $i 3] [lindex $i 5]]
    set archs [registry::property_retrieve $regref archs]
    if {$archs == 0} {
        set archs ""
    }
    return $archs
}

proc macports::getsourcepath {url} {
    global macports::portdbpath

    set source_path [split $url ://]

    if {[_source_is_snapshot $url]} {
        # daily snapshot tarball
        return [file join $portdbpath sources [join [lrange $source_path 3 end-1] /] ports]
    }

    return [file join $portdbpath sources [lindex $source_path 3] [lindex $source_path 4] [lindex $source_path 5]]
}

##
# Checks whether a supplied source URL is for a daily snapshot tarball
# (private)
#
# @param url source URL to check
# @return a list containing filename and extension or an empty list
proc _source_is_snapshot {url {filename ""} {extension ""}} {
    upvar $filename myfilename
    upvar $extension myextension

    if {[regexp {^(?:https?|ftp|rsync)://.+/(.+\.(tar\.gz|tar\.bz2|tar))$} $url -> f e]} {
        set myfilename $f
        set myextension $e

        return 1
    }

    return 0
}

proc macports::getportbuildpath {id {portname ""}} {
    global macports::portdbpath
    regsub {://} $id {.} port_path
    regsub -all {/} $port_path {_} port_path
    return [file join $portdbpath build $port_path $portname]
}

proc macports::getportlogpath {id {portname ""}} {
    global macports::portdbpath
    regsub {://} $id {.} port_path
    regsub -all {/} $port_path {_} port_path
    return [file join $portdbpath logs $port_path $portname]
}

proc macports::getportworkpath_from_buildpath {portbuildpath} {
    return [file join $portbuildpath work]
}

proc macports::getportworkpath_from_portdir {portpath {portname ""}} {
    return [macports::getportworkpath_from_buildpath [macports::getportbuildpath $portpath $portname]]
}

proc macports::getindex {source} {
    # Special case file:// sources
    if {[macports::getprotocol $source] == "file"} {
        return [file join [macports::getportdir $source] PortIndex]
    }

    return [file join [macports::getsourcepath $source] PortIndex]
}

proc mportsync {{optionslist {}}} {
    global macports::sources macports::portdbpath macports::rsync_options tcl_platform
    global macports::portverbose
    global macports::autoconf::rsync_path macports::autoconf::tar_path macports::autoconf::openssl_path
    array set options $optionslist
    if {[info exists options(no_reindex)]} {
        upvar $options(needed_portindex_var) any_needed_portindex
    }

    set numfailed 0

    ui_debug "Synchronizing ports tree(s)"
    foreach source $sources {
        set flags [lrange $source 1 end]
        set source [lindex $source 0]
        if {[lsearch -exact $flags nosync] != -1} {
            ui_debug "Skipping $source"
            continue
        }
        set needs_portindex 0
        ui_info "Synchronizing local ports tree from $source"
        switch -regexp -- [macports::getprotocol $source] {
            {^file$} {
                set portdir [macports::getportdir $source]
                if {[file exists $portdir/.svn]} {
                    set svn_commandline "[macports::findBinary svn] update --non-interactive ${portdir}"
                    ui_debug $svn_commandline
                    if {
                        [catch {
                            if {[getuid] == 0} {
                                set euid [geteuid]
                                set egid [getegid]
                                ui_debug "changing euid/egid - current euid: $euid - current egid: $egid"
                                setegid [name_to_gid [file attributes $portdir -group]]
                                seteuid [name_to_uid [file attributes $portdir -owner]]
                            }
                            system $svn_commandline
                            if {[getuid] == 0} {
                                seteuid $euid
                                setegid $egid
                            }
                        }]
                    } {
                        ui_debug "$::errorInfo"
                        ui_error "Synchronization of the local ports tree failed doing an svn update"
                        incr numfailed
                        continue
                    }
                }
                set needs_portindex 1
            }
            {^mports$} {
                macports::index::sync $macports::portdbpath $source
            }
            {^rsync$} {
                # Where to, boss?
                set indexfile [macports::getindex $source]
                set destdir [file dirname $indexfile]
                set is_tarball [_source_is_snapshot $source]
                file mkdir $destdir

                if {$is_tarball} {
                    set exclude_option ""
                    # need to do a few things before replacing the ports tree in this case
                    set destdir [file dirname $destdir]
                } else {
                    # Keep rsync happy with a trailing slash
                    if {[string index $source end] != "/"} {
                        append source "/"
                    }
                    # don't sync PortIndex yet; we grab the platform specific one afterwards
                    set exclude_option "'--exclude=/PortIndex*'"
                }
                # Do rsync fetch
                set rsync_commandline "${macports::autoconf::rsync_path} ${rsync_options} ${exclude_option} ${source} ${destdir}"
                ui_debug $rsync_commandline
                if {[catch {system $rsync_commandline}]} {
                    ui_error "Synchronization of the local ports tree failed doing rsync"
                    incr numfailed
                    continue
                }

                if {$is_tarball} {
                    # verify signature for tarball
                    global macports::archivefetch_pubkeys
                    set rsync_commandline "${macports::autoconf::rsync_path} ${rsync_options} ${exclude_option} ${source}.rmd160 ${destdir}"
                    ui_debug $rsync_commandline
                    if {[catch {system $rsync_commandline}]} {
                        ui_error "Synchronization of the ports tree signature failed doing rsync"
                        incr numfailed
                        continue
                    }
                    set tarball "${destdir}/[file tail $source]"
                    set signature "${tarball}.rmd160"
                    set openssl [macports::findBinary openssl $macports::autoconf::openssl_path]
                    set verified 0
                    foreach pubkey ${macports::archivefetch_pubkeys} {
                        if {![catch {exec $openssl dgst -ripemd160 -verify $pubkey -signature $signature $tarball} result]} {
                            set verified 1
                            ui_debug "successful verification with key $pubkey"
                            break
                        } else {
                            ui_debug "failed verification with key $pubkey"
                            ui_debug "openssl output: $result"
                        }
                    }
                    if {!$verified} {
                        ui_error "Failed to verify signature for ports tree!"
                        incr numfailed
                        continue
                    }

                    # extract tarball and move into place
                    set tar [macports::findBinary tar $macports::autoconf::tar_path]
                    file mkdir ${destdir}/tmp
                    set tar_cmd "$tar -C ${destdir}/tmp -xf ${tarball}"
                    ui_debug $tar_cmd
                    if {[catch {system $tar_cmd}]} {
                        ui_error "Failed to extract ports tree from tarball!"
                        incr numfailed
                        continue
                    }
                    # save the local PortIndex data
                    if {[file isfile $indexfile]} {
                        file copy -force $indexfile ${destdir}/
                        file rename -force $indexfile ${destdir}/tmp/ports/
                        if {[file isfile ${indexfile}.quick]} {
                            file rename -force ${indexfile}.quick ${destdir}/tmp/ports/
                        }
                    }
                    file delete -force ${destdir}/ports
                    file rename ${destdir}/tmp/ports ${destdir}/ports
                    file delete -force ${destdir}/tmp
                }

                set needs_portindex 1
                # now sync the index if the local file is missing or older than a day
                if {![file isfile $indexfile] || [expr [clock seconds] - [file mtime $indexfile]] > 86400
                      || [info exists options(no_reindex)]} {
                    if {$is_tarball} {
                        # chop ports.tar off the end
                        set index_source [string range $source 0 end-[string length [file tail $source]]]
                    } else {
                        set index_source $source 
                    }
                    set remote_indexfile "${index_source}PortIndex_${macports::os_platform}_${macports::os_major}_${macports::os_arch}/PortIndex"
                    set rsync_commandline "${macports::autoconf::rsync_path} ${rsync_options} $remote_indexfile ${destdir}"
                    ui_debug $rsync_commandline
                    if {[catch {system $rsync_commandline}]} {
                        ui_debug "Synchronization of the PortIndex failed doing rsync"
                    } else {
                        set ok 1
                        set needs_portindex 0
                        if {$is_tarball} {
                            set ok 0
                            set needs_portindex 1
                            # verify signature for PortIndex
                            set rsync_commandline "${macports::autoconf::rsync_path} ${rsync_options} ${remote_indexfile}.rmd160 ${destdir}"
                            ui_debug $rsync_commandline
                            if {![catch {system $rsync_commandline}]} {
                                foreach pubkey ${macports::archivefetch_pubkeys} {
                                    if {![catch {exec $openssl dgst -ripemd160 -verify $pubkey -signature ${destdir}/PortIndex.rmd160 ${destdir}/PortIndex} result]} {
                                        set ok 1
                                        set needs_portindex 0
                                        ui_debug "successful verification with key $pubkey"
                                        break
                                    } else {
                                        ui_debug "failed verification with key $pubkey"
                                        ui_debug "openssl output: $result"
                                    }
                                }
                                if {$ok} {
                                    # move PortIndex into place
                                    file rename -force ${destdir}/PortIndex ${destdir}/ports/
                                }
                            }
                        }
                        if {$ok} {
                            mports_generate_quickindex $indexfile
                        }
                    }
                }
                if {[catch {system "chmod -R a+r \"$destdir\""}]} {
                    ui_warn "Setting world read permissions on parts of the ports tree failed, need root?"
                }
            }
            {^https?$|^ftp$} {
                if {[_source_is_snapshot $source filename extension]} {
                    # sync a daily port snapshot tarball
                    set indexfile [macports::getindex $source]
                    set destdir [file dirname $indexfile]
                    set tarpath [file join [file normalize [file join $destdir ..]] $filename]

                    set updated 1
                    if {[file isdirectory $destdir]} {
                        set moddate [file mtime $destdir]
                        if {[catch {set updated [curl isnewer $source $moddate]} error]} {
                            ui_warn "Cannot check if $source was updated, ($error)"
                        }
                    }

                    if {(![info exists options(ports_force)] || $options(ports_force) != "yes") && $updated <= 0} {
                        ui_info "No updates for $source"
                        continue
                    }

                    file mkdir $destdir

                    set verboseflag {}
                    if {$macports::portverbose == "yes"} {
                        set verboseflag "-v"
                    }

                    if {[catch {eval curl fetch $verboseflag {$source} {$tarpath}} error]} {
                        ui_error "Fetching $source failed ($error)"
                        incr numfailed
                        continue
                    }

                    set extflag {}
                    switch $extension {
                        {tar.gz} {
                            set extflag "-z"
                        }
                        {tar.bz2} {
                            set extflag "-j"
                        }
                    }

                    set tar [macports::findBinary tar $macports::autoconf::tar_path]
                    if { [catch { system "cd $destdir/.. && $tar ${verboseflag} ${extflag} -xf $filename" } error] } {
                        ui_error "Extracting $source failed ($error)"
                        incr numfailed
                        continue
                    }

                    if {[catch {system "chmod -R a+r \"$destdir\""}]} {
                        ui_warn "Setting world read permissions on parts of the ports tree failed, need root?"
                    }

                    set platindex "PortIndex_${macports::os_platform}_${macports::os_major}_${macports::os_arch}/PortIndex"
                    if {[file isfile ${destdir}/${platindex}] && [file isfile ${destdir}/${platindex}.quick]} {
                        file rename -force "${destdir}/${platindex}" "${destdir}/${platindex}.quick" $destdir
                    }

                    file delete $tarpath
                } else {
                    # sync just a PortIndex file
                    set indexfile [macports::getindex $source]
                    file mkdir [file dirname $indexfile]
                    curl fetch ${source}/PortIndex $indexfile
                    curl fetch ${source}/PortIndex.quick ${indexfile}.quick
                }
            }
            default {
                ui_warn "Unknown synchronization protocol for $source"
            }
        }
        
        if {$needs_portindex} {
            set any_needed_portindex 1
            if {![info exists options(no_reindex)]} {
                global macports::prefix
                set indexdir [file dirname [macports::getindex $source]]
                if {[catch {system "${macports::prefix}/bin/portindex $indexdir"}]} {
                    ui_error "updating PortIndex for $source failed"
                }
            }
        }
    }

    # refresh the quick index if necessary (batch or interactive run)
    if {[info exists macports::ui_options(ports_commandfiles)]} {
        _mports_load_quickindex
    }

    if {$numfailed > 0} {
        return -code error "Synchronization of $numfailed source(s) failed"
    }
}

proc mportsearch {pattern {case_sensitive yes} {matchstyle regexp} {field name}} {
    global macports::portdbpath macports::sources
    set matches [list]
    set easy [expr { $field == "name" }]

    set found 0
    foreach source $sources {
        set source [lindex $source 0]
        set protocol [macports::getprotocol $source]
        if {$protocol == "mports"} {
            set res [macports::index::search $macports::portdbpath $source [list name $pattern]]
            eval lappend matches $res
        } else {
            if {[catch {set fd [open [macports::getindex $source] r]} result]} {
                ui_warn "Can't open index file for source: $source"
            } else {
                try {
                    incr found 1
                    while {[gets $fd line] >= 0} {
                        array unset portinfo
                        set name [lindex $line 0]
                        set len [lindex $line 1]
                        set line [read $fd $len]

                        if {$easy} {
                            set target $name
                        } else {
                            array set portinfo $line
                            if {![info exists portinfo($field)]} continue
                            set target $portinfo($field)
                        }

                        switch $matchstyle {
                            exact {
                                set matchres [expr 0 == ( {$case_sensitive == "yes"} ? [string compare $pattern $target] : [string compare -nocase $pattern $target] )]
                            }
                            glob {
                                set matchres [expr {$case_sensitive == "yes"} ? [string match $pattern $target] : [string match -nocase $pattern $target]]
                            }
                            regexp -
                            default {
                                set matchres [expr {$case_sensitive == "yes"} ? [regexp -- $pattern $target] : [regexp -nocase -- $pattern $target]]
                            }
                        }

                        if {$matchres == 1} {
                            if {$easy} {
                                array set portinfo $line
                            }
                            switch $protocol {
                                rsync {
                                    # Rsync files are local
                                    set source_url "file://[macports::getsourcepath $source]"
                                }
                                https -
                                http -
                                ftp {
                                    if {[_source_is_snapshot $source filename extension]} {
                                        # daily snapshot tarball
                                        set source_url "file://[macports::getsourcepath $source]"
                                    } else {
                                        # default action
                                        set source_url $source
                                    }
                                }
                                default {
                                    set source_url $source
                                }
                            }
                            if {[info exists portinfo(portarchive)]} {
                                set porturl ${source_url}/$portinfo(portarchive)
                            } elseif {[info exists portinfo(portdir)]} {
                                set porturl ${source_url}/$portinfo(portdir)
                            }
                            if {[info exists porturl]} {
                                lappend line porturl $porturl
                                ui_debug "Found port in $porturl"
                            } else {
                                ui_debug "Found port info: $line"
                            }
                            lappend matches $name
                            lappend matches $line
                        }
                    }
                } catch {*} {
                    ui_warn "It looks like your PortIndex file for $source may be corrupt."
                    throw
                } finally {
                    close $fd
                }
            }
        }
    }
    if {!$found} {
        return -code error "No index(es) found! Have you synced your source indexes?"
    }

    return $matches
}

# Returns the PortInfo for a single named port. The info comes from the
# PortIndex, and name matching is case-insensitive. Unlike mportsearch, only
# the first match is returned, but the return format is otherwise identical.
# The advantage is that mportlookup is much faster than mportsearch, due to
# the use of the quick index.
proc mportlookup {name} {
    global macports::portdbpath macports::sources

    set sourceno 0
    set matches [list]
    foreach source $sources {
        set source [lindex $source 0]
        set protocol [macports::getprotocol $source]
        if {$protocol != "mports"} {
            global macports::quick_index
            if {![info exists quick_index($sourceno,[string tolower $name])]} {
                incr sourceno 1
                continue
            }
            # The quick index is keyed on the port name, and provides the
            # offset in the main PortIndex where the given port's PortInfo
            # line can be found.
            set offset $quick_index($sourceno,[string tolower $name])
            incr sourceno 1
            if {[catch {set fd [open [macports::getindex $source] r]} result]} {
                ui_warn "Can't open index file for source: $source"
            } else {
                try {
                    seek $fd $offset
                    gets $fd line
                    set name [lindex $line 0]
                    set len [lindex $line 1]
                    set line [read $fd $len]

                    array set portinfo $line

                    switch $protocol {
                        rsync {
                            set source_url "file://[macports::getsourcepath $source]"
                        }
                        https -
                        http -
                        ftp {
                            if {[_source_is_snapshot $source filename extension]} {
                                set source_url "file://[macports::getsourcepath $source]"
                             } else {
                                set source_url $source
                             }
                        }
                        default {
                            set source_url $source
                        }
                    }
                    if {[info exists portinfo(portarchive)]} {
                        set porturl ${source_url}/$portinfo(portarchive)
                    } elseif {[info exists portinfo(portdir)]} {
                        set porturl ${source_url}/$portinfo(portdir)
                    }
                    if {[info exists porturl]} {
                        lappend line porturl $porturl
                    }
                    lappend matches $name
                    lappend matches $line
                    close $fd
                    set fd -1
                } catch {*} {
                    ui_warn "It looks like your PortIndex file for $source may be corrupt."
                } finally {
                    if {$fd != -1} {
                        close $fd
                    }
                }
                if {[llength $matches] > 0} {
                    break
                }
            }
        } else {
            set res [macports::index::search $macports::portdbpath $source [list name $name]]
            if {[llength $res] > 0} {
                eval lappend matches $res
                break
            }
        }
    }

    return $matches
}

# Returns all ports in the indices. Faster than 'mportsearch .*'
proc mportlistall {args} {
    global macports::portdbpath macports::sources
    set matches [list]

    set found 0
    foreach source $sources {
        set source [lindex $source 0]
        set protocol [macports::getprotocol $source]
        if {$protocol != "mports"} {
            if {![catch {set fd [open [macports::getindex $source] r]} result]} {
                try {
                    incr found 1
                    while {[gets $fd line] >= 0} {
                        array unset portinfo
                        set name [lindex $line 0]
                        set len [lindex $line 1]
                        set line [read $fd $len]

                        array set portinfo $line

                        switch $protocol {
                            rsync {
                                set source_url "file://[macports::getsourcepath $source]"
                            }
                            https -
                            http -
                            ftp {
                                if {[_source_is_snapshot $source filename extension]} {
                                    set source_url "file://[macports::getsourcepath $source]"
                                } else {
                                    set source_url $source
                                }
                            }
                            default {
                                set source_url $source
                            }
                        }
                        if {[info exists portinfo(portdir)]} {
                            set porturl ${source_url}/$portinfo(portdir)
                        } elseif {[info exists portinfo(portarchive)]} {
                            set porturl ${source_url}/$portinfo(portarchive)
                        }
                        if {[info exists porturl]} {
                            lappend line porturl $porturl
                        }
                        lappend matches $name $line
                    }
                } catch {*} {
                    ui_warn "It looks like your PortIndex file for $source may be corrupt."
                    throw
                } finally {
                    close $fd
                }
            } else {
                ui_warn "Can't open index file for source: $source"
            }
        } else {
            set res [macports::index::search $macports::portdbpath $source [list name .*]]
            eval lappend matches $res
        }
    }
    if {!$found} {
        return -code error "No index(es) found! Have you synced your source indexes?"
    }

    return $matches
}


# Loads PortIndex.quick from each source into the quick_index, generating
# it first if necessary.
proc _mports_load_quickindex {args} {
    global macports::sources macports::quick_index

    unset -nocomplain macports::quick_index

    set sourceno 0
    foreach source $sources {
        unset -nocomplain quicklist
        # chop off any tags
        set source [lindex $source 0]
        set index [macports::getindex $source]
        if {![file exists ${index}]} {
            continue
        }
        if {![file exists ${index}.quick]} {
            ui_warn "No quick index file found, attempting to generate one for source: $source"
            if {[catch {set quicklist [mports_generate_quickindex ${index}]}]} {
                continue
            }
        }
        # only need to read the quick index file if we didn't just update it
        if {![info exists quicklist]} {
            if {[catch {set fd [open ${index}.quick r]} result]} {
                ui_warn "Can't open quick index file for source: $source"
                continue
            } else {
                set quicklist [read $fd]
                close $fd
            }
        }
        foreach entry [split $quicklist "\n"] {
            set quick_index($sourceno,[lindex $entry 0]) [lindex $entry 1]
        }
        incr sourceno 1
    }
    if {!$sourceno} {
        ui_warn "No index(es) found! Have you synced your source indexes?"
    }
}

proc mports_generate_quickindex {index} {
    if {[catch {set indexfd [open ${index} r]} result] || [catch {set quickfd [open ${index}.quick w]} result]} {
        ui_warn "Can't open index file: $index"
        return -code error
    } else {
        try {
            set offset [tell $indexfd]
            set quicklist ""
            while {[gets $indexfd line] >= 0} {
                if {[llength $line] != 2} {
                    continue
                }
                set name [lindex $line 0]
                append quicklist "[string tolower $name] ${offset}\n"

                set len [lindex $line 1]
                read $indexfd $len
                set offset [tell $indexfd]
            }
            puts -nonewline $quickfd $quicklist
        } catch {*} {
            ui_warn "It looks like your PortIndex file $index may be corrupt."
            throw
        } finally {
            close $indexfd
            close $quickfd
        }
    }
    if {[info exists quicklist]} {
        return $quicklist
    } else {
        ui_warn "Failed to generate quick index for: $index"
        return -code error
    }
}

proc mportinfo {mport} {
    set workername [ditem_key $mport workername]
    return [$workername eval array get ::PortInfo]
}

proc mportclose {mport} {
    global macports::open_mports
    set refcnt [ditem_key $mport refcnt]
    incr refcnt -1
    ditem_key $mport refcnt $refcnt
    if {$refcnt == 0} {
        dlist_delete macports::open_mports $mport
        set workername [ditem_key $mport workername]
        # the hack in _mportexec might have already deleted the worker
        if {[interp exists $workername]} {
            interp delete $workername
        }
        ditem_delete $mport
    }
}

##### Private Depspec API #####
# This API should be considered work in progress and subject to change without notice.
##### "

# _mportkey
# - returns a variable from the port's interpreter

proc _mportkey {mport key} {
    set workername [ditem_key $mport workername]
    return [$workername eval "return \$${key}"]
}

# mportdepends builds the list of mports which the given port depends on.
# This list is added to $mport.
# This list actually depends on the target.
# This method can optionally recurse through the dependencies, looking for
#   dependencies of dependencies.
# This method can optionally cut the search when ports are already installed or
#   the dependencies are satisfied.
#
# mport -> mport item
# target -> target to consider the dependency for
# recurseDeps -> if the search should be recursive
# skipSatisfied -> cut the search tree when encountering installed/satisfied
#                  dependencies ports.
# accDeps -> accumulator for recursive calls
# return 0 if everything was ok, an non zero integer otherwise.
proc mportdepends {mport {target ""} {recurseDeps 1} {skipSatisfied 1} {accDeps 0}} {

    array set portinfo [mportinfo $mport]
    set deptypes {}
    if {$accDeps} {
        upvar depspec_seen depspec_seen
    } else {
        array set depspec_seen {}
    }

    # progress indicator
    if {![macports::ui_isset ports_debug]} {
        ui_info -nonewline "."
        flush stdout
    }
    
    if {[info exists portinfo(conflicts)] && ($target == "" || $target == "install" || $target == "activate")} {
        set conflictports [_mportconflictsinstalled $mport $portinfo(conflicts)]
        if {[llength ${conflictports}] != 0} {
            if {[macports::global_option_isset ports_force]} {
                ui_warn "Force option set; installing $portinfo(name) despite conflicts with: ${conflictports}"
            } else {
                if {![macports::ui_isset ports_debug]} {
                    ui_msg ""
                }
                return -code error "Can't install $portinfo(name) because conflicting ports are installed: ${conflictports}"
            }
        }
    }

    set workername [ditem_key $mport workername]
    set deptypes [macports::_deptypes_for_target $target $workername]

    set depPorts {}
    if {[llength $deptypes] > 0} {
        array set optionsarray [ditem_key $mport options]
        # avoid propagating requested flag from parent
        unset -nocomplain optionsarray(ports_requested)
        # subport will be different for deps
        unset -nocomplain optionsarray(subport)
        set options [array get optionsarray]
        set variations [ditem_key $mport variations]
        set required_archs [$workername eval get_canonical_archs]
        set depends_skip_archcheck [_mportkey $mport depends_skip_archcheck]
    }

    # Process the dependencies for each of the deptypes
    foreach deptype $deptypes {
        if {![info exists portinfo($deptype)]} {
            continue
        }
        foreach depspec $portinfo($deptype) {
            # skip depspec/archs combos we've already seen, and ones with less archs than ones we've seen
            set seenkey "${depspec},[join $required_archs ,]"
            set seen 0
            if {[info exists depspec_seen($seenkey)]} {
                set seen 1
            } else {
                set prev_seenkeys [array names depspec_seen ${depspec},*]
                set nrequired [llength $required_archs]
                foreach key $prev_seenkeys {
                    set key_archs [lrange [split $key ,] 1 end]
                    if {[llength $key_archs] > $nrequired} {
                        set seen 1
                        set seenkey $key
                        break
                    }
                }
            }
            if {$seen} {
                if {$depspec_seen($seenkey) != 0} {
                    # nonzero means the dep is not satisfied, so we have to record it
                    ditem_append_unique $mport requires $depspec_seen($seenkey)
                }
                continue
            }
            
            # Is that dependency satisfied or this port installed?
            # If we don't skip or if it is not, add it to the list.
            set present [_mportispresent $mport $depspec]

            # get the portname that satisfies the depspec
            set dep_portname [$workername eval _get_dep_port $depspec]
            if {!$skipSatisfied && $dep_portname == ""} {
                set dep_portname [lindex [split $depspec :] end]
            }

            set check_archs 0
            if {$dep_portname != "" && $deptype != "depends_fetch" && $deptype != "depends_extract" && [lsearch -exact $depends_skip_archcheck $dep_portname] == -1} {
                set check_archs 1
            }

            # need to open the portfile even if the dep is installed if it doesn't have the right archs
            set parse 0
            if {!$skipSatisfied || !$present || ($check_archs && ![macports::_active_supports_archs $dep_portname $required_archs])} {
                set parse 1
            }
            if {$parse} {
                # Find the porturl
                if {[catch {set res [mportlookup $dep_portname]} error]} {
                    global errorInfo
                    ui_msg ""
                    ui_debug "$errorInfo"
                    ui_error "Internal error: port lookup failed: $error"
                    return 1
                }

                array unset dep_portinfo
                array set dep_portinfo [lindex $res 1]
                if {![info exists dep_portinfo(porturl)]} {
                    if {![macports::ui_isset ports_debug]} {
                        ui_msg ""
                    }
                    ui_error "Dependency '$dep_portname' not found."
                    return 1
                } elseif {[info exists dep_portinfo(installs_libs)] && !$dep_portinfo(installs_libs)} {
                    set check_archs 0
                }
                lappend options subport $dep_portname
                # Figure out the depport. Check the open_mports list first, since
                # we potentially leak mport references if we mportopen each time,
                # because mportexec only closes each open mport once.
                set depport [dlist_match_multi $macports::open_mports [list porturl $dep_portinfo(porturl) options $options variations $variations]]
                
                if {$depport == {}} {
                    # We haven't opened this one yet.
                    set depport [mportopen $dep_portinfo(porturl) $options $variations]
                }
            }

            # check archs
            if {$parse && $check_archs
                && ![macports::_mport_supports_archs $depport $required_archs]} {

                set supported_archs [_mportkey $depport supported_archs]
                mportclose $depport
                set arch_mismatch 1
                set has_universal 0
                if {[info exists dep_portinfo(variants)] && [lsearch -exact $dep_portinfo(variants) universal] != -1} {
                    # a universal variant is offered
                    set has_universal 1
                    array unset variation_array
                    array set variation_array $variations
                    if {![info exists variation_array(universal)] || $variation_array(universal) != "+"} {
                        set variation_array(universal) +
                        # try again with +universal
                        set depport [mportopen $dep_portinfo(porturl) $options [array get variation_array]]
                        if {[macports::_mport_supports_archs $depport $required_archs]} {
                            set arch_mismatch 0
                        }
                    }
                }
                if {$arch_mismatch} {
                    macports::_explain_arch_mismatch [_mportkey $mport subport] $dep_portname $required_archs $supported_archs $has_universal
                    return -code error "architecture mismatch"
                }
            }

            if {$parse} {
                if {$recurseDeps} {
                    # Add to the list we need to recurse on.
                    lappend depPorts $depport
                }

                # Append the sub-port's provides to the port's requirements list.
                set depport_provides "[ditem_key $depport provides]"
                ditem_append_unique $mport requires $depport_provides
                set depspec_seen($seenkey) $depport_provides
            } else {
                set depspec_seen($seenkey) 0
            }
        }
    }

    # Loop on the depports.
    if {$recurseDeps} {
        foreach depport $depPorts {
            # Sub ports should be installed (all dependencies must be satisfied).
            set res [mportdepends $depport "" $recurseDeps $skipSatisfied 1]
            if {$res != 0} {
                return $res
            }
        }
    }

    return 0
}

# check if the given mport can support dependents with the given archs
proc macports::_mport_supports_archs {mport required_archs} {
    if {$required_archs == "noarch"} {
        return 1
    }
    set workername [ditem_key $mport workername]
    set provided_archs [$workername eval get_canonical_archs]
    if {$provided_archs == "noarch"} {
        return 1
    }
    foreach arch $required_archs {
        if {[lsearch -exact $provided_archs $arch] == -1} {
            return 0
        }
    }
    return 1
}

# check if the active version of a port supports the given archs
proc macports::_active_supports_archs {portname required_archs} {
    if {$required_archs == "noarch"} {
        return 1
    }
    if {[catch {set ilist [registry::active $portname]}]} {
        return 0
    }
    set i [lindex $ilist 0]
    set regref [registry::open_entry $portname [lindex $i 1] [lindex $i 2] [lindex $i 3] [lindex $i 5]]
    set provided_archs [registry::property_retrieve $regref archs]
    if {$provided_archs == "noarch" || $provided_archs == "" || $provided_archs == 0} {
        return 1
    }
    foreach arch $required_archs {
        if {[lsearch -exact $provided_archs $arch] == -1} {
            return 0
        }
    }
    return 1
}

# print an error message explaining why a port's archs are not provided by a dependency
proc macports::_explain_arch_mismatch {port dep required_archs supported_archs has_universal} {
    global macports::universal_archs
    if {![macports::ui_isset ports_debug]} {
        ui_msg ""
    }
    ui_error "Cannot install $port for the arch(s) '$required_archs' because"
    if {$supported_archs != ""} {
        foreach arch $required_archs {
            if {[lsearch -exact $supported_archs $arch] == -1} {
                ui_error "its dependency $dep only supports the arch(s) '$supported_archs'."
                return
            }
        }
    }
    if {$has_universal} {
        foreach arch $required_archs {
            if {[lsearch -exact $universal_archs $arch] == -1} {
                ui_error "its dependency $dep does not build for the required arch(s) by default"
                ui_error "and the configured universal_archs '$universal_archs' are not sufficient."
                return
            }
        }
        ui_error "its dependency $dep cannot build for the required arch(s)."
        return
    }
    ui_error "its dependency $dep does not build for the required arch(s) by default"
    ui_error "and does not have a universal variant."
}

# check if the given mport has any dependencies of the given types
proc macports::_mport_has_deptypes {mport deptypes} {
    array set portinfo [mportinfo $mport]
    foreach type $deptypes {
        if {[info exists portinfo($type)] && $portinfo($type) != ""} {
            return 1
        }
    }
    return 0
}

# check if the given target needs dependencies installed first
proc macports::_target_needs_deps {target} {
    # XXX: need a better way than checking this hardcoded list
    switch -- $target {
        fetch -
        checksum -
        extract -
        patch -
        configure -
        build -
        test -
        destroot -
        install -
        activate -
        dmg -
        mdmg -
        pkg -
        mpkg -
        rpm -
        dpkg -
        srpm { return 1 }
        default { return 0 }
    }
}

# Determine dependency types required for target
proc macports::_deptypes_for_target {target workername} {
    switch $target {
        fetch       -
        checksum    { return "depends_fetch" }
        extract     -
        patch       { return "depends_fetch depends_extract" }
        configure   -
        build       { return "depends_fetch depends_extract depends_build depends_lib" }
        test        -
        srpm        -
        destroot    { return "depends_fetch depends_extract depends_build depends_lib depends_run" }
        dmg         -
        pkg         -
        mdmg        -
        mpkg        -
        rpm         -
        dpkg        {
            if {[$workername eval _archive_available]} {
                return "depends_lib depends_run"
            } else {
                return "depends_fetch depends_extract depends_build depends_lib depends_run"
            }
        }
        install     -
        activate    -
        ""          {
            if {[$workername eval registry_exists \$subport \$version \$revision \$portvariants]
                || [$workername eval _archive_available]} {
                return "depends_lib depends_run"
            } else {
                return "depends_fetch depends_extract depends_build depends_lib depends_run"
            }
        }
    }
    return ""
}

# selfupdate procedure
proc macports::selfupdate {{optionslist {}} {updatestatusvar ""}} {
    global macports::prefix macports::portdbpath macports::libpath macports::rsync_server macports::rsync_dir macports::rsync_options
    global macports::autoconf::macports_version macports::autoconf::rsync_path tcl_platform
    global macports::autoconf::openssl_path macports::autoconf::tar_path
    array set options $optionslist
    
    # variable that indicates whether we actually updated base
    if {$updatestatusvar != ""} {
        upvar $updatestatusvar updatestatus
        set updatestatus no
    }

    # are we syncing a tarball? (implies detached signature)
    set is_tarball 0
    if {[string range ${rsync_dir} end-3 end] == ".tar"} {
        set is_tarball 1
        set mp_source_path [file join $portdbpath sources ${rsync_server} [file dirname ${rsync_dir}]]
    } else {
        if {[string index $rsync_dir end] != "/"} {
            append rsync_dir "/"
        }
        set mp_source_path [file join $portdbpath sources ${rsync_server} ${rsync_dir}]
    }
    # create the path to the to be downloaded sources if it doesn't exist
    if {![file exists $mp_source_path]} {
        file mkdir $mp_source_path
    }
    ui_debug "MacPorts sources location: $mp_source_path"

    # sync the MacPorts sources
    ui_msg "--->  Updating MacPorts base sources using rsync"
    if { [catch { system "$rsync_path $rsync_options rsync://${rsync_server}/${rsync_dir} $mp_source_path" } result ] } {
       return -code error "Error synchronizing MacPorts sources: $result"
    }

    if {$is_tarball} {
        # verify signature for tarball
        global macports::archivefetch_pubkeys
        if { [catch { system "$rsync_path $rsync_options rsync://${rsync_server}/${rsync_dir}.rmd160 $mp_source_path" } result ] } {
            return -code error "Error synchronizing MacPorts source signature: $result"
        }
        set openssl [findBinary openssl $macports::autoconf::openssl_path]
        set tarball "${mp_source_path}/[file tail $rsync_dir]"
        set signature "${tarball}.rmd160"
        set verified 0
        foreach pubkey ${macports::archivefetch_pubkeys} {
            if {![catch {exec $openssl dgst -ripemd160 -verify $pubkey -signature $signature $tarball} result]} {
                set verified 1
                ui_debug "successful verification with key $pubkey"
                break
            } else {
                ui_debug "failed verification with key $pubkey"
                ui_debug "openssl output: $result"
            }
        }
        if {!$verified} {
            return -code error "Failed to verify signature for MacPorts source!"
        }
        
        # extract tarball and move into place
        set tar [macports::findBinary tar $macports::autoconf::tar_path]
        file mkdir ${mp_source_path}/tmp
        set tar_cmd "$tar -C ${mp_source_path}/tmp -xf ${tarball}"
        ui_debug $tar_cmd
        if {[catch {system $tar_cmd}]} {
            return -code error "Failed to extract MacPorts sources from tarball!"
        }
        file delete -force ${mp_source_path}/base
        file rename ${mp_source_path}/tmp/base ${mp_source_path}/base
        file delete -force ${mp_source_path}/tmp
        # set the final extracted source path
        set mp_source_path ${mp_source_path}/base
    }

    # echo current MacPorts version
    ui_msg "MacPorts base version $macports::autoconf::macports_version installed,"

    if { [info exists options(ports_force)] && $options(ports_force) == "yes" } {
        set use_the_force_luke yes
        ui_debug "Forcing a rebuild and reinstallation of MacPorts"
    } else {
        set use_the_force_luke no
        ui_debug "Rebuilding and reinstalling MacPorts if needed"
    }

    # Choose what version file to use: old, floating point format or new, real version number format
    set version_file [file join $mp_source_path config macports_version]
    if {[file exists $version_file]} {
        set fd [open $version_file r]
        gets $fd macports_version_new
        close $fd
        # echo downloaded MacPorts version
        ui_msg "MacPorts base version $macports_version_new downloaded."
    } else {
        ui_warn "No version file found, please rerun selfupdate."
        set macports_version_new 0
    }

    # check if we we need to rebuild base
    set comp [rpm-vercomp $macports_version_new $macports::autoconf::macports_version]

    # syncing ports tree.
    if {![info exists options(ports_selfupdate_nosync)] || $options(ports_selfupdate_nosync) != "yes"} {
        ui_msg "--->  Updating the ports tree"
        if {$comp > 0} {
            # updated portfiles potentially need new base to parse - tell sync to try to 
            # use prefabricated PortIndex files and signal if it couldn't
            lappend optionslist no_reindex 1 needed_portindex_var needed_portindex
        }
        if {[catch {mportsync $optionslist} result]} {
            return -code error "Couldn't sync the ports tree: $result"
        }
    }

    if {$use_the_force_luke == "yes" || $comp > 0} {
        if {[info exists options(ports_dryrun)] && $options(ports_dryrun) == "yes"} {
            ui_msg "--->  MacPorts base is outdated, selfupdate would install $macports_version_new (dry run)"
        } else {
            ui_msg "--->  MacPorts base is outdated, installing new version $macports_version_new"

            # get installation user/group and permissions
            set owner [file attributes ${prefix} -owner]
            set group [file attributes ${prefix} -group]
            set perms [string range [file attributes ${prefix} -permissions] end-3 end]
            if {$tcl_platform(user) != "root" && ![string equal $tcl_platform(user) $owner]} {
                return -code error "User $tcl_platform(user) does not own ${prefix} - try using sudo"
            }
            ui_debug "Permissions OK"

            # where to install a link to our macports1.0 tcl package
            set mp_tclpackage_path [file join $portdbpath .tclpackage]
            if { [file exists $mp_tclpackage_path]} {
                set fd [open $mp_tclpackage_path r]
                gets $fd tclpackage
                close $fd
            } else {
                set tclpackage $libpath
            }

            set configure_args "--prefix=$prefix --with-tclpackage=$tclpackage --with-install-user=$owner --with-install-group=$group --with-directory-mode=$perms"
            # too many users have an incompatible readline in /usr/local, see ticket #10651
            if {$tcl_platform(os) != "Darwin" || $prefix == "/usr/local"
                || ([glob -nocomplain "/usr/local/lib/lib{readline,history}*"] == "" && [glob -nocomplain "/usr/local/include/readline/*.h"] == "")} {
                append configure_args " --enable-readline"
            } else {
                ui_warn "Disabling readline support due to readline in /usr/local"
            }

            if {$prefix == "/usr/local"} {
                append configure_args " --with-unsupported-prefix"
            }

            # Choose a sane compiler
            set cc_arg ""
            if {$::macports::os_platform == "darwin"} {
                set cc_arg "CC=/usr/bin/cc "
            }

            # do the actual configure, build and installation of new base
            ui_msg "Installing new MacPorts release in $prefix as $owner:$group; permissions $perms; Tcl-Package in $tclpackage\n"
            if { [catch { system "cd $mp_source_path && ${cc_arg}./configure $configure_args && make && make install SELFUPDATING=1" } result] } {
                return -code error "Error installing new MacPorts base: $result"
            }
            if {[info exists updatestatus]} {
                set updatestatus yes
            }
        }
    } elseif {$comp < 0} {
        ui_msg "--->  MacPorts base is probably trunk or a release candidate"
    } else {
        ui_msg "--->  MacPorts base is already the latest version"
    }

    # set the MacPorts sources to the right owner
    set sources_owner [file attributes [file join $portdbpath sources/] -owner]
    ui_debug "Setting MacPorts sources ownership to $sources_owner"
    if { [catch { exec [findBinary chown $macports::autoconf::chown_path] -R $sources_owner [file join $portdbpath sources/] } result] } {
        return -code error "Couldn't change permissions of the MacPorts sources at $mp_source_path to $sources_owner: $result"
    }

    if {![info exists options(ports_selfupdate_nosync)] || $options(ports_selfupdate_nosync) != "yes"} {
        if {[info exists needed_portindex]} {
            ui_msg "Not all sources could be fully synced using the old version of MacPorts."
            ui_msg "Please run selfupdate again now that MacPorts base has been updated."
        } else {
            ui_msg "\nThe ports tree has been updated. To upgrade your installed ports, you should run"
            ui_msg "  port upgrade outdated"
        }
    }

    return 0
}

# upgrade API wrapper procedure
# return codes: 0 = success, 1 = general failure, 2 = port name not found in index
proc macports::upgrade {portname dspec variationslist optionslist {depscachename ""}} {
    # only installed ports can be upgraded
    if {![registry::entry_exists_for_name $portname]} {
        ui_error "$portname is not installed"
        return 1
    }
    if {![string match "" $depscachename]} {
        upvar $depscachename depscache
    } else {
        array set depscache {}
    }
    # stop upgrade from being called via mportexec as well
    set orig_nodeps yes
    if {![info exists macports::global_options(ports_nodeps)]} {
        set macports::global_options(ports_nodeps) yes
        set orig_nodeps no
    }
    
    # run the actual upgrade
    set status [macports::_upgrade $portname $dspec $variationslist $optionslist depscache]
    
    if {!$orig_nodeps} {
        unset -nocomplain macports::global_options(ports_nodeps)
    }
    return $status
}

# main internal upgrade procedure
proc macports::_upgrade {portname dspec variationslist optionslist {depscachename ""}} {
    global macports::global_variations
    array set options $optionslist
    set options(subport) $portname

    if {![string match "" $depscachename]} {
        upvar $depscachename depscache
    }

    # Is this a dry run?
    set is_dryrun no
    if {[info exists options(ports_dryrun)] && $options(ports_dryrun) eq "yes"} {
        set is_dryrun yes
    }

    # check if the port is in tree
    if {[catch {mportlookup $portname} result]} {
        global errorInfo
        ui_debug "$errorInfo"
        ui_error "port lookup failed: $result"
        return 1
    }
    # argh! port doesnt exist!
    if {$result == ""} {
        ui_warn "No port $portname found in the index."
        return 2
    }
    # fill array with information
    array set portinfo [lindex $result 1]
    # set portname again since the one we were passed may not have had the correct case
    set portname $portinfo(name)

    set ilist {}
    if { [catch {set ilist [registry::installed $portname ""]} result] } {
        if {$result == "Registry error: $portname not registered as installed." } {
            ui_debug "$portname is *not* installed by MacPorts"

            # We need to pass _mportispresent a reference to the mport that is
            # actually declaring the dependency on the one we're checking for.
            # We got here via _upgrade_dependencies, so we grab it from 2 levels up.
            upvar 2 workername parentworker
            if {![_mportispresent $parentworker $dspec ] } {
                # open porthandle
                set porturl $portinfo(porturl)
                if {![info exists porturl]} {
                    set porturl file://./
                }
                # Grab the variations from the parent
                upvar 2 variations variations

                if {[catch {set workername [mportopen $porturl [array get options] [array get variations]]} result]} {
                    global errorInfo
                    ui_debug "$errorInfo"
                    ui_error "Unable to open port: $result"
                    return 1
                }
                # While we're at it, update the portinfo
                array unset portinfo
                array set portinfo [mportinfo $workername]
                
                # upgrade its dependencies first
                set status [_upgrade_dependencies portinfo depscache variationslist options yes]
                if {$status != 0 && $status != 2 && ![ui_isset ports_processall]} {
                    catch {mportclose $workername}
                    return $status
                }
                # now install it
                if {[catch {set result [mportexec $workername activate]} result]} {
                    global errorInfo
                    ui_debug "$errorInfo"
                    ui_error "Unable to exec port: $result"
                    catch {mportclose $workername}
                    return 1
                }
                if {$result > 0} {
                    ui_error "Problem while installing $portname"
                    catch {mportclose $workername}
                    return $result
                }
                # we just installed it, so mark it done in the cache
                set depscache(port:${portname}) 1
                mportclose $workername
            } else {
                # dependency is satisfied by something other than the named port
                ui_debug "$portname not installed, soft dependency satisfied"
                # mark this depspec as satisfied in the cache
                set depscache($dspec) 1
            }
            # the rest of the proc doesn't matter for a port that is freshly
            # installed or not installed
            return 0
        } else {
            ui_error "Checking installed version failed: $result"
            return 1
        }
    } else {
        # we'll now take care of upgrading it, so we can add it to the cache
        set depscache(port:${portname}) 1
    }
    
    # set version_in_tree and revision_in_tree
    if {![info exists portinfo(version)]} {
        ui_error "Invalid port entry for $portname, missing version"
        return 1
    }
    set version_in_tree "$portinfo(version)"
    set revision_in_tree "$portinfo(revision)"
    set epoch_in_tree "$portinfo(epoch)"

    # find latest version installed and active version (if any)
    set anyactive no
    set version_installed {}
    foreach i $ilist {
        set variant [lindex $i 3]
        set version [lindex $i 1]
        set revision [lindex $i 2]
        set epoch [lindex $i 5]
        if { $version_installed == {} || ($epoch > $epoch_installed && $version != $version_installed) ||
                ($epoch >= $epoch_installed && [rpm-vercomp $version $version_installed] > 0)
                || ($epoch >= $epoch_installed
                    && [rpm-vercomp $version $version_installed] == 0
                    && $revision > $revision_installed)} {
            set version_installed $version
            set revision_installed $revision
            set variant_installed $variant
            set epoch_installed $epoch
        }

        set isactive [lindex $i 4]
        if {$isactive == 1} {
            set anyactive yes
            set version_active $version
            set revision_active $revision
            set variant_active $variant
            set epoch_active $epoch
        }
    }

    # output version numbers
    ui_debug "epoch: in tree: $epoch_in_tree installed: $epoch_installed"
    ui_debug "$portname ${version_in_tree}_${revision_in_tree} exists in the ports tree"
    ui_debug "$portname ${version_installed}_${revision_installed} $variant_installed is the latest installed"
    if {$anyactive} {
        ui_debug "$portname ${version_active}_${revision_active} $variant_active is active"
        # save existing variant for later use
        set oldvariant $variant_active
        set regref [registry::open_entry $portname $version_active $revision_active $variant_active $epoch_active]
    } else {
        ui_debug "no version of $portname is active"
        set oldvariant $variant_installed
        set regref [registry::open_entry $portname $version_installed $revision_installed $variant_installed $epoch_installed]
    }
    set oldnegatedvariant [registry::property_retrieve $regref negated_variants]
    if {$oldnegatedvariant == 0} {
        set oldnegatedvariant {}
    }
    set requestedflag [registry::property_retrieve $regref requested]
    set os_platform_installed [registry::property_retrieve $regref os_platform]
    set os_major_installed [registry::property_retrieve $regref os_major]

    # Before we do
    # dependencies, we need to figure out the final variants,
    # open the port, and update the portinfo.
    set porturl $portinfo(porturl)
    if {![info exists porturl]} {
        set porturl file://./
    }

    # Note $variationslist is left alone and so retains the original
    # requested variations, which should be passed to recursive calls to
    # upgrade; while variations gets existing variants and global variations
    # merged in later on, so it applies only to this port's upgrade
    array set variations $variationslist
    
    set globalvarlist [array get macports::global_variations]

    set minusvariant [lrange [split $oldnegatedvariant -] 1 end]
    set plusvariant [lrange [split $oldvariant +] 1 end]
    ui_debug "Merging existing variants '${oldvariant}${oldnegatedvariant}' into variants"
    set oldvariantlist [list]
    foreach v $plusvariant {
        lappend oldvariantlist $v "+"
    }
    foreach v $minusvariant {
        lappend oldvariantlist $v "-"
    }

    # merge in the old variants
    foreach {variation value} $oldvariantlist {
        if { ![info exists variations($variation)]} {
            set variations($variation) $value
        }
    }

    # Now merge in the global (i.e. variants.conf) variations.
    # We wait until now so that existing variants for this port
    # override global variations
    foreach { variation value } $globalvarlist {
        if { ![info exists variations($variation)] } {
            set variations($variation) $value
        }
    }

    ui_debug "new fully merged portvariants: [array get variations]"
    
    # at this point we need to check if a different port will be replacing this one
    if {[info exists portinfo(replaced_by)] && ![info exists options(ports_upgrade_no-replace)]} {
        ui_msg "--->  $portname is replaced by $portinfo(replaced_by)"
        if {[catch {mportlookup $portinfo(replaced_by)} result]} {
            global errorInfo
            ui_debug "$errorInfo"
            ui_error "port lookup failed: $result"
            return 1
        }
        if {$result == ""} {
            ui_error "No port $portinfo(replaced_by) found."
            return 1
        }
        array unset portinfo
        array set portinfo [lindex $result 1]
        set newname $portinfo(name)

        set porturl $portinfo(porturl)
        if {![info exists porturl]} {
            set porturl file://./
        }
        set depscache(port:${newname}) 1
    } else {
        set newname $portname
    }

    array set interp_options [array get options]
    set interp_options(ports_requested) $requestedflag
    set interp_options(subport) $newname

    if {[catch {set workername [mportopen $porturl [array get interp_options] [array get variations]]} result]} {
        global errorInfo
        ui_debug "$errorInfo"
        ui_error "Unable to open port: $result"
        return 1
    }
    array unset interp_options

    array unset portinfo
    array set portinfo [mportinfo $workername]
    set version_in_tree "$portinfo(version)"
    set revision_in_tree "$portinfo(revision)"
    set epoch_in_tree "$portinfo(epoch)"

    set build_override 0
    set will_install yes
    # check installed version against version in ports
    if { ( [rpm-vercomp $version_installed $version_in_tree] > 0
            || ([rpm-vercomp $version_installed $version_in_tree] == 0
                && [rpm-vercomp $revision_installed $revision_in_tree] >= 0 ))
        && ![info exists options(ports_upgrade_force)] } {
        if {$portname != $newname} { 
            ui_debug "ignoring versions, installing replacement port"
        } elseif { $epoch_installed < $epoch_in_tree } {
            set build_override 1
            ui_debug "epoch override ... upgrading!"
        } elseif {[info exists options(ports_upgrade_enforce-variants)] && $options(ports_upgrade_enforce-variants) eq "yes"
                  && [info exists portinfo(canonical_active_variants)] && $portinfo(canonical_active_variants) != $oldvariant} {
            ui_debug "variant override ... upgrading!"
        } elseif {$os_platform_installed != "" && $os_major_installed != "" && $os_platform_installed != 0
                  && ([_mportkey $workername "{os.platform}"] != $os_platform_installed
                  || [_mportkey $workername "{os.major}"] != $os_major_installed)} {
            ui_debug "platform mismatch ... upgrading!"
            set build_override 1
        } else {
            if {[info exists portinfo(canonical_active_variants)] && $portinfo(canonical_active_variants) != $oldvariant} {
                if {[llength $variationslist] > 0} {
                    ui_warn "Skipping upgrade since $portname ${version_installed}_${revision_installed} >= $portname ${version_in_tree}_${revision_in_tree}, even though installed variants \"$oldvariant\" do not match \"$portinfo(canonical_active_variants)\". Use 'upgrade --enforce-variants' to switch to the requested variants."
                } else {
                    ui_debug "Skipping upgrade since $portname ${version_installed}_${revision_installed} >= $portname ${version_in_tree}_${revision_in_tree}, even though installed variants \"$oldvariant\" do not match \"$portinfo(canonical_active_variants)\"."
                }
            } else {
                ui_debug "No need to upgrade! $portname ${version_installed}_${revision_installed} >= $portname ${version_in_tree}_${revision_in_tree}"
            }
            set will_install no
        }
    }

    set will_build no
    # avoid building again unnecessarily
    if {$will_install && ([info exists options(ports_upgrade_force)] || $build_override == 1
        || ![registry::entry_exists $newname $version_in_tree $revision_in_tree $portinfo(canonical_active_variants)])} {
        set will_build yes
    }

    # first upgrade dependencies
    if {![info exists options(ports_nodeps)]} {
        set status [_upgrade_dependencies portinfo depscache variationslist options $will_build]
        if {$status != 0 && $status != 2 && ![ui_isset ports_processall]} {
            catch {mportclose $workername}
            return $status
        }
    } else {
        ui_debug "Not following dependencies"
    }

    if {!$will_install} {
        # nothing to do for this port, so just check if we have to do dependents
        if {[info exists options(ports_do_dependents)]} {
            # We do dependents ..
            set options(ports_nodeps) 1

            registry::open_dep_map
            if {$anyactive} {
                set deplist [registry::list_dependents $portname $version_active $revision_active $variant_active]
            } else {
                set deplist [registry::list_dependents $portname $version_installed $revision_installed $variant_installed]
            }

            if { [llength deplist] > 0 } {
                foreach dep $deplist {
                    set mpname [lindex $dep 2]
                    if {![llength [array get depscache port:${mpname}]]} {
                        set status [macports::_upgrade $mpname port:${mpname} $variationslist [array get options] depscache]
                        if {$status != 0 && $status != 2 && ![ui_isset ports_processall]} {
                            catch {mportclose $workername}
                            return $status
                        }
                    }
                }
            }
        }
        mportclose $workername
        return 0
    }

    if {$will_build} {
        # install version_in_tree (but don't activate yet)
        if {[catch {set result [mportexec $workername install]} result] || $result != 0} {
            if {[info exists ::errorInfo]} {
                ui_debug "$::errorInfo"
            }
            ui_error "Unable to upgrade port: $result"
            catch {mportclose $workername}
            return 1
        }
    }

    # are we installing an existing version due to force or epoch override?
    if {[registry::entry_exists $newname $version_in_tree $revision_in_tree $portinfo(canonical_active_variants)]
        && ([info exists options(ports_upgrade_force)] || $build_override == 1)} {
         ui_debug "Uninstalling $newname ${version_in_tree}_${revision_in_tree}$portinfo(canonical_active_variants)"
        # we have to force the uninstall in case of dependents
        set force_cur [info exists options(ports_force)]
        set options(ports_force) yes
        set existing_epoch [lindex [lindex [registry::installed $newname ${version_in_tree}_${revision_in_tree}$portinfo(canonical_active_variants)] 0] 5]
        set newregref [registry::open_entry $newname $version_in_tree $revision_in_tree $portinfo(canonical_active_variants) $existing_epoch]
        if {$is_dryrun eq "yes"} {
            ui_msg "Skipping uninstall $newname @${version_in_tree}_${revision_in_tree}$portinfo(canonical_active_variants) (dry run)"
        } elseif {![registry::run_target $newregref uninstall [array get options]]
                  && [catch {registry_uninstall::uninstall $newname $version_in_tree $revision_in_tree $portinfo(canonical_active_variants) [array get options]} result]} {
            global errorInfo
            ui_debug "$errorInfo"
            ui_error "Uninstall $newname ${version_in_tree}_${revision_in_tree}$portinfo(canonical_active_variants) failed: $result"
            catch {mportclose $workername}
            return 1
        }
        if {!$force_cur} {
            unset options(ports_force)
        }
        if {$anyactive && $version_in_tree == $version_active && $revision_in_tree == $revision_active
            && $portinfo(canonical_active_variants) == $variant_active && $portname == $newname} {
            set anyactive no
        }
    }
    if {$anyactive && $portname != $newname} {
        # replaced_by in effect, deactivate the old port
        # we have to force the deactivate in case of dependents
        set force_cur [info exists options(ports_force)]
        set options(ports_force) yes
        if {$is_dryrun eq "yes"} {
            ui_msg "Skipping deactivate $portname @${version_active}_${revision_active}${variant_active} (dry run)"
        } elseif {![catch {registry::active $portname}] &&
                  ![registry::run_target $regref deactivate [array get options]]
                  && [catch {portimage::deactivate $portname $version_active $revision_active $variant_active [array get options]} result]} {
            global errorInfo
            ui_debug "$errorInfo"
            ui_error "Deactivating $portname @${version_active}_${revision_active}${variant_active} failed: $result"
            catch {mportclose $workername}
            return 1
        }
        if {!$force_cur} {
            unset options(ports_force)
        }
        set anyactive no
    }
    if {[info exists options(port_uninstall_old)] && $portname == $newname} {
        # uninstalling now could fail due to dependents when not forced,
        # because the new version is not installed
        set uninstall_later yes
    }

    if {$is_dryrun eq "yes"} {
        if {$anyactive} {
            ui_msg "Skipping deactivate $portname @${version_active}_${revision_active}${variant_active} (dry run)"
        }
        ui_msg "Skipping activate $newname @${version_in_tree}_${revision_in_tree}$portinfo(canonical_active_variants) (dry run)"
    } elseif {[catch {set result [mportexec $workername activate]} result]} {
        global errorInfo
        ui_debug "$errorInfo"
        ui_error "Couldn't activate $newname ${version_in_tree}_${revision_in_tree}$portinfo(canonical_active_variants): $result"
        catch {mportclose $workername}
        return 1
    }

    # Check if we have to do dependents
    if {[info exists options(ports_do_dependents)]} {
        # We do dependents ..
        set options(ports_nodeps) 1

        registry::open_dep_map
        if {$portname != $newname} {
            set deplist [registry::list_dependents $newname $version_in_tree $revision_in_tree $portinfo(canonical_active_variants)]
        } else {
            set deplist [list]
        }
        if {$anyactive} {
            set deplist [concat $deplist [registry::list_dependents $portname $version_active $revision_active $variant_active]]
        } else {
            set deplist [concat $deplist [registry::list_dependents $portname $version_installed $revision_installed $variant_installed]]
        }

        if { [llength deplist] > 0 } {
            foreach dep $deplist {
                set mpname [lindex $dep 2]
                if {![llength [array get depscache port:${mpname}]]} {
                    set status [macports::_upgrade $mpname port:${mpname} $variationslist [array get options] depscache]
                    if {$status != 0 && $status != 2 && ![ui_isset ports_processall]} {
                        catch {mportclose $workername}
                        return $status
                    }
                }
            }
        }
    }

    if {[info exists uninstall_later] && $uninstall_later == yes} {
        foreach i $ilist {
            set version [lindex $i 1]
            set revision [lindex $i 2]
            set variant [lindex $i 3]
            if {$version == $version_in_tree && $revision == $revision_in_tree && $variant == $portinfo(canonical_active_variants) && $portname == $newname} {
                continue
            }
            set epoch [lindex $i 5]
            ui_debug "Uninstalling $portname ${version}_${revision}${variant}"
            set regref [registry::open_entry $portname $version $revision $variant $epoch]
            if {$is_dryrun eq "yes"} {
                ui_msg "Skipping uninstall $portname @${version}_${revision}${variant} (dry run)"
            } elseif {![registry::run_target $regref uninstall $optionslist]
                      && [catch {registry_uninstall::uninstall $portname $version $revision $variant $optionslist} result]} {
                global errorInfo
                ui_debug "$errorInfo"
                # replaced_by can mean that we try to uninstall all versions of the old port, so handle errors due to dependents
                if {$result != "Please uninstall the ports that depend on $portname first." && ![ui_isset ports_processall]} {
                    ui_error "Uninstall $portname @${version}_${revision}${variant} failed: $result"
                    catch {mportclose $workername}
                    return 1
                }
            }
        }
    }

    # close the port handle
    mportclose $workername
    return 0
}

# upgrade_dependencies: helper proc for upgrade
# Calls upgrade on each dependency listed in the PortInfo.
# Uses upvar to access the variables.
proc macports::_upgrade_dependencies {portinfoname depscachename variationslistname optionsname {build_needed yes}} {
    upvar $portinfoname portinfo $depscachename depscache \
          $variationslistname variationslist \
          $optionsname options
    upvar workername parentworker

    # If we're following dependents, we only want to follow this port's
    # dependents, not those of all its dependencies. Otherwise, we would
    # end up processing this port's dependents n+1 times (recursively!),
    # where n is the number of dependencies this port has, since this port
    # is of course a dependent of each of its dependencies. Plus the
    # dependencies could have any number of unrelated dependents.

    # So we save whether we're following dependents, unset the option
    # while doing the dependencies, and restore it afterwards.
    set saved_do_dependents [info exists options(ports_do_dependents)]
    unset -nocomplain options(ports_do_dependents)

    set status 0
    # each required dep type is upgraded
    if {$build_needed} {
        set dtypes {depends_fetch depends_extract depends_build depends_lib depends_run}
    } else {
        set dtypes {depends_lib depends_run}
    }
    foreach dtype $dtypes {
        if {[info exists portinfo($dtype)]} {
            foreach i $portinfo($dtype) {
                set parent_interp [ditem_key $parentworker workername]
                set d [$parent_interp eval _get_dep_port $i]
                if {![llength [array get depscache port:${d}]] && ![llength [array get depscache $i]]} {
                    if {$d != ""} {
                        set dspec port:$d
                    } else {
                        set dspec $i
                        set d [lindex [split $i :] end]
                    }
                    set status [macports::_upgrade $d $dspec $variationslist [array get options] depscache]
                    if {$status != 0 && $status != 2 && ![ui_isset ports_processall]} break
                }
            }
        }
        if {$status != 0 && $status != 2 && ![ui_isset ports_processall]} break
    }
    # restore dependent-following to its former value
    if {$saved_do_dependents} {
        set options(ports_do_dependents) yes
    }
    return $status
}

# mportselect
#   * command: The only valid commands are list, set and show
#   * group: This argument should correspond to a directory under
#            $macports::prefix/etc/select.
#   * version: This argument is only used by the 'set' command.
# On error mportselect returns with the code 'error'.
proc mportselect {command group {version ""}} {
    ui_debug "mportselect \[$command] \[$group] \[$version]"

    set conf_path "$macports::prefix/etc/select/$group"
    if {![file isdirectory $conf_path]} {
        return -code error "The specified group '$group' does not exist."
    }

    switch -- $command {
        list {
            if {[catch {set versions [glob -directory $conf_path *]} result]} {
                global errorInfo
                ui_debug "$result: $errorInfo"
                return -code error [concat "No configurations associated " \
                                           "with '$group' were found."]
            }

            # Return the sorted list of versions (excluding base and current).
            set lversions {}
            foreach v $versions {
                # Only the file name corresponds to the version name.
                set v [file tail $v]
                if {$v eq "base" || $v eq "current"} {
                    continue
                }
                lappend lversions [file tail $v]
            }
            return [lsort $lversions]
        }
        set {
            # Use $conf_path/$version to read in sources.
            if {$version == "" || $version == "base" || $version == "current"
                    || [catch {set src_file [open "$conf_path/$version"]} result]} {
                global errorInfo
                ui_debug "$result: $errorInfo"
                return -code error "The specified version '$version' is not valid."
            }
            set srcs [split [read -nonewline $src_file] "\n"]
            close $src_file

            # Use $conf_path/base to read in targets.
            if {[catch {set tgt_file [open "$conf_path/base"]} result]} {
                global errorInfo
                ui_debug "$result: $errorInfo"
                return -code error [concat "The configuration file " \
                                           "'$conf_path/base' could not be " \
                                           "opened."]
            }
            set tgts [split [read -nonewline $tgt_file] "\n"]
            close $tgt_file

            # Iterate through the configuration files executing the specified
            # actions.
            set i 0
            foreach tgt $tgts {
                set src [lindex $srcs $i]

                switch -glob -- $src {
                    - {
                        # The source is unavailable for this file.
                        set tgt [file join $macports::prefix $tgt]
                        file delete $tgt
                        ui_debug "rm -f $tgt"
                    }
                    /* {
                        # The source is an absolute path.
                        set tgt [file join $macports::prefix $tgt]
                        file delete $tgt
                        file link -symbolic $tgt $src
                        ui_debug "ln -sf $src $tgt"
                    }
                    default {
                        # The source is a relative path.
                        set src [file join $macports::prefix $src]
                        set tgt [file join $macports::prefix $tgt]
                        file delete $tgt
                        file link -symbolic $tgt $src
                        ui_debug "ln -sf $src $tgt"
                    }
                }
                set i [expr $i+1]
            }

            # Update the selected version.
            set selected_version "$conf_path/current"
            if {[file exists $selected_version]} {
                file delete $selected_version
            }
            symlink $version $selected_version
            return
        }
        show {
            set selected_version "$conf_path/current"

            if {![file exists $selected_version]} {
                return "none"
            } else {
                return [file readlink $selected_version]
            }
        }
    }
    return
}

# Return a good temporary directory to use; /tmp if TMPDIR is not set
# in the environment
proc macports::gettmpdir {args} {
    global env

    if {[info exists env(TMPDIR)]} {
        return $env(TMPDIR)
    } else {
        return "/tmp"
    }
}
