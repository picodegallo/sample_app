# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4
# $Id: portarchivefetch.tcl 80587 2011-07-15 14:09:49Z jmr@macports.org $
#
# Copyright (c) 2002 - 2003 Apple Inc.
# Copyright (c) 2004 - 2011 The MacPorts Project
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

package provide portarchivefetch 1.0
package require fetch_common 1.0
package require portutil 1.0
package require Pextlib 1.0

set org.macports.archivefetch [target_new org.macports.archivefetch portarchivefetch::archivefetch_main]
target_init ${org.macports.archivefetch} portarchivefetch::archivefetch_init
target_provides ${org.macports.archivefetch} archivefetch
target_requires ${org.macports.archivefetch} main
target_prerun ${org.macports.archivefetch} portarchivefetch::archivefetch_start

namespace eval portarchivefetch {
    variable archivefetch_urls {}
}

options archive_sites archivefetch.user archivefetch.password \
    archivefetch.use_epsv archivefetch.ignore_sslcert \
    archive_sites.mirror_subdir archivefetch.pubkeys \
    archive.subdir

# user name & password
default archivefetch.user ""
default archivefetch.password ""
# Use EPSV for FTP transfers
default archivefetch.use_epsv no
# Ignore SSL certificate
default archivefetch.ignore_sslcert no
default archivefetch.pubkeys {$archivefetch_pubkeys}

default archive_sites {[portarchivefetch::filter_sites]}
default archive_sites.listfile {"archive_sites.tcl"}
default archive_sites.listpath {"port1.0/fetch"}
default archive.subdir {${subport}}

proc portarchivefetch::filter_sites {} {
    global prefix porturl
    set mirrorfile [get_full_archive_sites_path]
    if {[file exists $mirrorfile]} {
        source $mirrorfile
    }
    set ret {}
    foreach site [array names portfetch::mirror_sites::archive_prefix] {
        if {$portfetch::mirror_sites::archive_prefix($site) == $prefix} {
            lappend ret $site
        }
    }
    if {[file rootname [file tail $porturl]] == [file rootname [file tail [get_portimage_path]]]} {
        lappend ret [string range $porturl 0 end-[string length [file tail $porturl]]]
        archive.subdir
    }
    return $ret
}

set_ui_prefix

# Checks possible archive files to assemble url lists for later fetching
proc portarchivefetch::checkarchivefiles {urls} {
    global all_archive_files archivefetch.fulldestpath portarchivetype \
           version revision portvariants archive_sites
    upvar $urls fetch_urls

    # Define archive directory path
    set archive.path [get_portimage_path]
    set archivefetch.fulldestpath [file dirname ${archive.path}]

    # throws an error if unsupported
    archiveTypeIsSupported $portarchivetype

    set archive.file [file tail ${archive.path}]
    lappend all_archive_files ${archive.file}
    if {[info exists archive_sites]} {
        lappend fetch_urls archive_sites ${archive.file}
    }
}

# returns full path to mirror list file
proc portarchivefetch::get_full_archive_sites_path {} {
    global archive_sites.listfile archive_sites.listpath porturl
    return [getportresourcepath $porturl [file join ${archive_sites.listpath} ${archive_sites.listfile}]]
}

# Perform the full checksites/checkarchivefiles sequence.
proc portarchivefetch::checkfiles {urls} {
    upvar $urls fetch_urls

    portfetch::checksites [list archive_sites [list {} {} ARCHIVE_SITE_LOCAL]] \
                          [get_full_archive_sites_path]
    checkarchivefiles fetch_urls
}


# Perform a standard fetch, assembling fetch urls from
# the listed url variable and associated archive file
proc portarchivefetch::fetchfiles {args} {
    global archivefetch.fulldestpath UI_PREFIX
    global archivefetch.user archivefetch.password archivefetch.use_epsv \
           archivefetch.ignore_sslcert
    global portverbose ports_binary_only
    variable archivefetch_urls
    variable ::portfetch::urlmap

    if {![file isdirectory ${archivefetch.fulldestpath}]} {
        if {[catch {file mkdir ${archivefetch.fulldestpath}} result]} {
            elevateToRoot "archivefetch"
            set elevated yes
            if {[catch {file mkdir ${archivefetch.fulldestpath}} result]} {
                return -code error [format [msgcat::mc "Unable to create archive path: %s"] $result]
            }
        }
    }
    set incoming_path [file join [option portdbpath] incoming]
    if {![file isdirectory $incoming_path]} {
        if {[catch {file mkdir $incoming_path} result]} {
            elevateToRoot "archivefetch"
            set elevated yes
            if {[catch {file mkdir $incoming_path} result]} {
                return -code error [format [msgcat::mc "Unable to create archive fetch path: %s"] $result]
            }
        }
    }
    chownAsRoot ${archivefetch.fulldestpath}
    chownAsRoot $incoming_path
    if {[info exists elevated] && $elevated == yes} {
        dropPrivileges
    }

    set fetch_options {}
    if {[string length ${archivefetch.user}] || [string length ${archivefetch.password}]} {
        lappend fetch_options -u
        lappend fetch_options "${archivefetch.user}:${archivefetch.password}"
    }
    if {${archivefetch.use_epsv} != "yes"} {
        lappend fetch_options "--disable-epsv"
    }
    if {${archivefetch.ignore_sslcert} != "no"} {
        lappend fetch_options "--ignore-ssl-cert"
    }
    if {$portverbose == "yes"} {
        lappend fetch_options "-v"
    }
    set sorted no

    foreach {url_var archive} $archivefetch_urls {
        if {![file isfile ${archivefetch.fulldestpath}/${archive}]} {
            ui_info "$UI_PREFIX [format [msgcat::mc "%s doesn't seem to exist in %s"] $archive ${archivefetch.fulldestpath}]"
            if {![file writable ${archivefetch.fulldestpath}]} {
                return -code error [format [msgcat::mc "%s must be writable"] ${archivefetch.fulldestpath}]
            }
            if {![file writable $incoming_path]} {
                return -code error [format [msgcat::mc "%s must be writable"] $incoming_path]
            }
            if {!$sorted} {
                portfetch::sortsites archivefetch_urls {} archive_sites
                set sorted yes
            }
            if {![info exists urlmap($url_var)]} {
                ui_error [format [msgcat::mc "No defined site for tag: %s, using archive_sites"] $url_var]
                set urlmap($url_var) $urlmap(archive_sites)
            }
            unset -nocomplain fetched
            foreach site $urlmap($url_var) {
                if {[string index $site end] != "/"} {
                    append site "/[option archive.subdir]"
                } else {
                    append site [option archive.subdir]
                }
                ui_msg "$UI_PREFIX [format [msgcat::mc "Attempting to fetch %s from %s"] $archive ${site}]"
                set file_url [portfetch::assemble_url $site $archive]
                set effectiveURL ""
                if {![catch {eval curl fetch --effective-url effectiveURL $fetch_options {$file_url} {"${incoming_path}/${archive}.TMP"}} result]} {
                    # Successful fetch
                    set fetched 1
                    break
                } else {
                    ui_debug "[msgcat::mc "Fetching archive failed:"]: $result"
                    file delete -force "${incoming_path}/${archive}.TMP"
                }
            }
            if {[info exists fetched]} {
                # there should be an rmd160 digest of the archive signed with one of the trusted keys
                set signature "${incoming_path}/${archive}.rmd160"
                ui_msg "$UI_PREFIX [format [msgcat::mc "Attempting to fetch %s from %s"] ${archive}.rmd160 $site]"
                # reusing $file_url from the last iteration of the loop above
                if {[catch {eval curl fetch --effective-url effectiveURL $fetch_options {${file_url}.rmd160} {$signature}} result]} {
                    ui_debug "$::errorInfo"
                    return -code error "Failed to fetch signature for archive: $result"
                }
                set openssl [findBinary openssl $portutil::autoconf::openssl_path]
                set verified 0
                foreach pubkey [option archivefetch.pubkeys] {
                    if {![catch {exec $openssl dgst -ripemd160 -verify $pubkey -signature $signature "${incoming_path}/${archive}.TMP"} result]} {
                        set verified 1
                        break
                    } else {
                        ui_debug "failed verification with key $pubkey"
                        ui_debug "openssl output: $result"
                    }
                }
                if {!$verified} {
                    return -code error "Failed to verify signature for archive!"
                }
                if {[catch {file rename -force "${incoming_path}/${archive}.TMP" "${archivefetch.fulldestpath}/${archive}"} result]} {
                    ui_debug "$::errorInfo"
                    return -code error "Failed to move downloaded archive into place: $result"
                }
                file delete -force $signature
                set archive_exists 1
            }
        } else {
            set archive_exists 1
        }
    }
    if {[info exists archive_exists]} {
        # modify state file to skip remaining phases up to destroot
        global target_state_fd
        foreach target {fetch checksum extract patch configure build destroot} {
            write_statefile target "org.macports.${target}" $target_state_fd
        }
        return 0
    }
    if {[info exists ports_binary_only] && $ports_binary_only == "yes"} {
        return -code error "archivefetch failed for [option subport] @[option version]_[option revision][option portvariants]"
    } else {
        return 0
    }
}

# Initialize archivefetch target and call checkfiles.
proc portarchivefetch::archivefetch_init {args} {
    global porturl portarchivetype
    # installing straight from a binary archive
    if {[file rootname [file tail $porturl]] == [file rootname [file tail [get_portimage_path]]] && [file extension $porturl] != ""} {
        set portarchivetype [string range [file extension $porturl] 1 end]
    }
    return 0
}

proc portarchivefetch::archivefetch_start {args} {
    variable archivefetch_urls
    global UI_PREFIX subport all_archive_files ports_source_only
    if {![tbool ports_source_only]} {
        portarchivefetch::checkfiles archivefetch_urls
    }
    if {[info exists all_archive_files] && [llength $all_archive_files] > 0} {
        ui_msg "$UI_PREFIX [format [msgcat::mc "Fetching archive for %s"] $subport]"
    }
}

# Main archive fetch routine
# just calls the standard fetchfiles procedure
proc portarchivefetch::archivefetch_main {args} {
    global all_archive_files
    if {[info exists all_archive_files] && [llength $all_archive_files] > 0} {
        # Fetch the files
        portarchivefetch::fetchfiles
    }
    return 0
}
