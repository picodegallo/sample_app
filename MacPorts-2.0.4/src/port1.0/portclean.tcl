# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4
# portclean.tcl
# $Id: portclean.tcl 80444 2011-07-13 10:00:40Z jmr@macports.org $
#
# Copyright (c) 2005-2007, 2009-2011 The MacPorts Project
# Copyright (c) 2004 Robert Shaw <rshaw@opendarwin.org>
# Copyright (c) 2002 - 2003 Apple Inc.
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

# the 'clean' target is provided by this package

package provide portclean 1.0
package require portutil 1.0
package require Pextlib 1.0

set org.macports.clean [target_new org.macports.clean portclean::clean_main]
target_runtype ${org.macports.clean} always
target_state ${org.macports.clean} no
target_provides ${org.macports.clean} clean
target_requires ${org.macports.clean} main
target_prerun ${org.macports.clean} portclean::clean_start

namespace eval portclean {
}

set_ui_prefix

proc portclean::clean_start {args} {
    global UI_PREFIX prefix

    ui_notice "$UI_PREFIX [format [msgcat::mc "Cleaning %s"] [option subport]]"

    if {[getuid] == 0 && [geteuid] != 0} {
        elevateToRoot "clean"
    }
}

proc portclean::clean_main {args} {
    global UI_PREFIX
    global ports_clean_dist ports_clean_work ports_clean_logs
    global ports_clean_all keeplogs usealtworkpath

    if {$usealtworkpath} {
        ui_warn "Only cleaning in ~/.macports; insufficient privileges for standard locations"
    }

    if {[info exists ports_clean_all] && $ports_clean_all == "yes" || \
        [info exists ports_clean_dist] && $ports_clean_dist == "yes"} {
        ui_info "$UI_PREFIX [format [msgcat::mc "Removing distfiles for %s"] [option subport]]"
        clean_dist
    }
    if {[info exists ports_clean_all] && $ports_clean_all == "yes" || \
        [info exists ports_clean_work] && $ports_clean_work == "yes" || \
        !([info exists ports_clean_logs] && $ports_clean_logs == "yes")} {
         ui_info "$UI_PREFIX [format [msgcat::mc "Removing work directory for %s"] [option subport]]"
         clean_work
    }
    if {(([info exists ports_clean_logs] && $ports_clean_logs == "yes") || ($keeplogs == "no"))
        && !$usealtworkpath} {
        clean_logs
    }

    return 0
}

#
# Remove the directory where the distfiles reside.
# This is crude, but works.
#
proc portclean::clean_dist {args} {
    global name ports_force distpath dist_subdir distfiles patchfiles usealtworkpath portdbpath altprefix

    # remove known distfiles for sure (if they exist)
    set count 0
    foreach file $distfiles {
        set distfile [getdistname $file]
        ui_debug "Looking for $distfile"
        set distfile [file join $distpath $distfile]
        if {[file isfile $distfile]} {
            ui_debug "Removing file: $distfile"
            if {[catch {delete $distfile} result]} {
                ui_debug "$::errorInfo"
                ui_error "$result"
            }
            incr count
        }
        if {!$usealtworkpath && [file isfile ${altprefix}${distfile}]} {
            ui_debug "Removing file: ${altprefix}${distfile}"
            if {[catch {delete ${altprefix}${distfile}} result]} {
                ui_debug "$::errorInfo"
                ui_error "$result"
            }
            incr count
        }
    }
    if {$count > 0} {
        ui_debug "$count distfile(s) removed."
    } else {
        ui_debug "No distfiles found to remove at $distpath"
    }

    set count 0
    if {![info exists patchfiles]} {
        set patchfiles ""
    }
    foreach file $patchfiles {
        set patchfile [getdistname $file]
        ui_debug "Looking for $patchfile"
        set patchfile [file join $distpath $patchfile]
        if {[file isfile $patchfile]} {
            ui_debug "Removing file: $patchfile"
            if {[catch {delete $patchfile} result]} {
                ui_debug "$::errorInfo"
                ui_error "$result"
            }
            incr count
        }
        if {!$usealtworkpath && [file isfile ${altprefix}${patchfile}]} {
            ui_debug "Removing file: ${altprefix}${patchfile}"
            if {[catch {delete ${altprefix}${patchfile}} result]} {
                ui_debug "$::errorInfo"
                ui_error "$result"
            }
            incr count
        }
    }
    if {$count > 0} {
        ui_debug "$count patchfile(s) removed."
    } else {
        ui_debug "No patchfiles found to remove at $distpath"
    }

    # next remove dist_subdir if only needed for this port,
    # or if user forces us to
    set dirlist [list]
    if {$dist_subdir != $name} {
        if {!([info exists ports_force] && $ports_force == "yes")
            && [file isdirectory $distpath]
            && [llength [readdir $distpath]] > 0} {
            ui_warn [format [msgcat::mc "Distfiles directory '%s' may contain distfiles needed for other ports, use the -f flag to force removal" ] $distpath]
        } else {
            lappend dirlist $dist_subdir
            lappend dirlist $name
        }
    } else {
        lappend dirlist $name
    }
    # loop through directories
    set count 0
    foreach dir $dirlist {
        if {$usealtworkpath} {
            set distdir [file join ${altprefix}${portdbpath} distfiles $dir]
        } else {
            set distdir [file join ${portdbpath} distfiles $dir]
        }
        if {[file isdirectory $distdir]} {
            ui_debug "Removing directory: ${distdir}"
            if {[catch {delete $distdir} result]} {
                ui_debug "$::errorInfo"
                ui_error "$result"
            }
            incr count
        }
        if {!$usealtworkpath && [file isdirectory ${altprefix}${distdir}]} {
            ui_debug "Removing directory: ${altprefix}${distdir}"
            if {[catch {delete ${altprefix}${distdir}} result]} {
                ui_debug "$::errorInfo"
                ui_error "$result"
            }
            incr count
        }
    }
    if {$count > 0} {
        ui_debug "$count distfile directory(s) removed."
    } else {
        ui_debug "No distfile directory found to remove."
    }
    return 0
}

proc portclean::clean_work {args} {
    global portbuildpath subbuildpath worksymlink usealtworkpath altprefix portpath

    if {[file isdirectory $subbuildpath]} {
        ui_debug "Removing directory: ${subbuildpath}"
        if {[catch {delete $subbuildpath} result]} {
            ui_debug "$::errorInfo"
            ui_error "$result"
        }
        # silently fail if non-empty (other subports might be using portbuildpath)
        catch {file delete $portbuildpath}
    } else {
        ui_debug "No work directory found to remove at ${subbuildpath}"
    }

    if {!$usealtworkpath && [file isdirectory ${altprefix}${subbuildpath}]} {
        ui_debug "Removing directory: ${altprefix}${subbuildpath}"
        if {[catch {delete ${altprefix}${subbuildpath}} result]} {
            ui_debug "$::errorInfo"
            ui_error "$result"
        }
        catch {file delete ${altprefix}${portbuildpath}}
    } else {
        ui_debug "No work directory found to remove at ${altprefix}${subbuildpath}"
    }

    # Clean symlink, if necessary
    if {![catch {file type $worksymlink} result] && $result eq "link"} {
        ui_debug "Removing symlink: $worksymlink"
        delete $worksymlink
    }
    
    # clean port dir in alt prefix
    if {[file exists "${altprefix}${portpath}"]} {
        ui_debug "removing ${altprefix}${portpath}"
        delete "${altprefix}${portpath}"
    }

    return 0
}
proc portclean::clean_logs {args} {
    global portpath portbuildpath worksymlink portverbose keeplogs prefix subport
    set logpath [getportlogpath $portpath]
    set subdir [file join $logpath $subport]
  	if {[file isdirectory $subdir]} {
        ui_debug "Removing directory: ${subdir}"
        if {[catch {delete $subdir} result]} {
            ui_debug "$::errorInfo"
            ui_error "$result"
        }
        catch {file delete $logpath}
    } else {
        ui_debug "No log directory found to remove at ${logpath}"
    }           	
    return 0
}
