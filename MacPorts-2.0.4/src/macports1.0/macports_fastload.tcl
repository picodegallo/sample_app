# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4
# macports_fastload.tcl.in
# $Id: macports_fastload.tcl.in 79597 2011-06-19 20:59:11Z jmr@macports.org $
#
# Copyright (c) 2005-2007, 2009-2010 The MacPorts Project
# Copyright (c) 2004-2005 Paul Guyot, The MacPorts Project.
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
# 3. Neither the name of The MacPorts Project nor the names of its contributors
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

# This script is here to fast load all the MacPorts related packages.
# This avoids the very expensive globbing of Tcl' package mechanism.
# Please note that this is not required and base/ should work even if some
# packages are moved as long as their new location is in Tcl's package paths.
# However, this file also defines a workaround to avoid conflicts between a /
# installation of MacPorts and a user installation of MacPorts (on the same box).
# (this workaround isn't required on 10.4.2).
#
# The package command that's replaced in this code works somewhat differently
# than the original version. In particular, users with multiple copies of a
# package such as portuninstall (due to obsolete files being left from previous
# installations) may experience problems due to different package loading
# behavior.
#
if { [regexp {\d+\.\d+\.\d+} [info patchlevel]] &&
        ([package vcompare [info patchlevel] 8.4.7] < 0) } {
    global allpackages
    if {![info exists allpackages]} {
        # Only patch once.
        array set allpackages {}
        rename package package_native
        proc package {args} {
            global allpackages
            if {([lindex $args 0] == "ifneeded") && ([llength $args] == 4)} {
                set package_name [lindex $args 1]
                set package_version [lindex $args 2]
                set package_key ${package_name}::${package_version}
                if {![info exists allpackages($package_key)]} {
                    set allpackages($package_key) 1
                    set result [eval package_native $args]
                    } else {
                        set result ""
                    }
            } else {
                set result [eval package_native $args]
            }
            return $result
        }
    }
}

set sharetcldir [file normalize [file join [file dirname [info script]] ..]]
if {[file exists $sharetcldir]} {
    foreach dir [glob -directory $sharetcldir *] {
        set pkgindex [file join $dir pkgIndex.tcl]
        if [file exists $pkgindex] {
            source $pkgindex
        }
    }
}

if { "/usr/lib/sqlite3" != "" } {
    set dir "/usr/lib/sqlite3"
    set pkgindex [file join $dir pkgIndex.tcl]
    if [file exists $pkgindex] {
        source $pkgindex
    }
}
