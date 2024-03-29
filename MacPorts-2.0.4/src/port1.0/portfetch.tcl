# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4
# portfetch.tcl
# $Id: portfetch.tcl 83538 2011-09-05 10:36:27Z raimue@macports.org $
#
# Copyright (c) 2004 - 2011 The MacPorts Project
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

package provide portfetch 1.0
package require fetch_common 1.0
package require portutil 1.0
package require Pextlib 1.0

set org.macports.fetch [target_new org.macports.fetch portfetch::fetch_main]
target_init ${org.macports.fetch} portfetch::fetch_init
target_provides ${org.macports.fetch} fetch
target_requires ${org.macports.fetch} main
target_prerun ${org.macports.fetch} portfetch::fetch_start

namespace eval portfetch {
    namespace export suffix
    variable fetch_urls {}
}

# define options: distname master_sites
options master_sites patch_sites extract.suffix distfiles patchfiles use_bzip2 use_lzma use_xz use_zip use_7z use_dmg dist_subdir \
    fetch.type fetch.user fetch.password fetch.use_epsv fetch.ignore_sslcert \
    master_sites.mirror_subdir patch_sites.mirror_subdir \
    bzr.url bzr.revision \
    cvs.module cvs.root cvs.password cvs.date cvs.tag cvs.method \
    svn.url svn.revision svn.method \
    git.cmd git.url git.branch \
    hg.cmd hg.url hg.tag

# XXX we use the command framework to buy us some useful features,
# but this is not a user-modifiable command
commands bzr
commands cvs
commands svn

# Defaults
default extract.suffix .tar.gz
default fetch.type standard

default bzr.cmd {[findBinary bzr $portutil::autoconf::bzr_path]}
default bzr.dir {${workpath}}
default bzr.revision {-1}
default bzr.pre_args {"--builtin --no-aliases checkout --lightweight"}
default bzr.args ""
default bzr.post_args {"-r ${bzr.revision} ${bzr.url} ${worksrcdir}"}

default cvs.cmd {[findBinary cvs $portutil::autoconf::cvs_path]}
default cvs.password ""
default cvs.dir {${workpath}}
default cvs.method {export}
default cvs.module {$distname}
default cvs.tag ""
default cvs.date ""
default cvs.env {CVS_PASSFILE=${workpath}/.cvspass}
default cvs.pre_args {"-z9 -f -d ${cvs.root}"}
default cvs.args ""
default cvs.post_args {"${cvs.module}"}

default svn.cmd {[portfetch::find_svn_path]}
default svn.dir {${workpath}}
default svn.method {export}
default svn.revision ""
default svn.env {}
default svn.pre_args {"--non-interactive --trust-server-cert"}
default svn.args ""
default svn.post_args ""

default git.cmd {[findBinary git $portutil::autoconf::git_path]}
default git.dir {${workpath}}
default git.branch {}

default hg.cmd {[findBinary hg $portutil::autoconf::hg_path]}
default hg.dir {${workpath}}
default hg.tag {tip}

# Set distfiles
default distfiles {[list [portfetch::suffix $distname]]}
default dist_subdir {${name}}

# user name & password
default fetch.user ""
default fetch.password ""
# Use EPSV for FTP transfers
default fetch.use_epsv "yes"
# Ignore SSL certificate
default fetch.ignore_sslcert "no"
# Use remote timestamps
default fetch.remote_time "no"

default fallback_mirror_site "macports"
default global_mirror_site "macports_distfiles"
default mirror_sites.listfile {"mirror_sites.tcl"}
default mirror_sites.listpath {"port1.0/fetch"}

# Deprecation
option_deprecate svn.tag svn.revision

# Option-executed procedures
option_proc use_bzip2 portfetch::set_extract_type
option_proc use_lzma  portfetch::set_extract_type
option_proc use_xz    portfetch::set_extract_type
option_proc use_zip   portfetch::set_extract_type
option_proc use_7z    portfetch::set_extract_type
option_proc use_dmg   portfetch::set_extract_type

option_proc fetch.type portfetch::set_fetch_type

proc portfetch::set_extract_type {option action args} {
    global extract.suffix
    if {[string equal ${action} "set"] && [tbool args]} {
        switch $option {
            use_bzip2 {
                set extract.suffix .tar.bz2
            }
            use_lzma {
                set extract.suffix .tar.lzma
                depends_extract-append bin:lzma:xz
            }
            use_xz {
                set extract.suffix .tar.xz
                depends_extract-append bin:xz:xz
            }
            use_zip {
                set extract.suffix .zip
                depends_extract-append bin:unzip:unzip
            }
            use_7z {
                set extract.suffix .7z
                depends_extract-append bin:7za:p7zip
            }
            use_dmg {
                set extract.suffix .dmg
            }
        }
    }
}

proc portfetch::set_fetch_type {option action args} {
    global os.platform os.major
    if {[string equal ${action} "set"]} {
        if {$args != "standard"} {
            distfiles
        }
        switch $args {
            bzr {
                depends_fetch-append bin:bzr:bzr
            }
            cvs {
                depends_fetch-append bin:cvs:cvs
            }
            svn {
                if {${os.platform} == "darwin" && ${os.major} >= 10} {
                    depends_fetch-append bin:svn:subversion
                } else {
                    depends_fetch-append port:subversion
                }
            }
            git {
                depends_fetch-append bin:git:git-core
            }
            hg {
                depends_fetch-append bin:hg:mercurial
            }
        }
    }
}

proc portfetch::find_svn_path {args} {
    global prefix os.platform os.major
    # Snow Leopard is the first Mac OS X version to include a recent enough svn (1.6.x) to support the --trust-server-cert option.
    if {${os.platform} == "darwin" && ${os.major} >= 10} {
        return [findBinary svn $portutil::autoconf::svn_path]
    } else {
        return ${prefix}/bin/svn
    }
}

set_ui_prefix


# Given a distname, return the distname with extract.suffix appended
proc portfetch::suffix {distname} {
    global extract.suffix
    return "${distname}${extract.suffix}"
}
# XXX import suffix into the global namespace as it is currently used from
# Portfiles, but should better go somewhere else
namespace import portfetch::suffix

# Checks patch files and their tags to assemble url lists for later fetching
proc portfetch::checkpatchfiles {urls} {
    global patchfiles all_dist_files patch_sites filespath
    upvar $urls fetch_urls

    if {[info exists patchfiles]} {
        foreach file $patchfiles {
            if {![file exists "${filespath}/${file}"]} {
                set distsite [getdisttag $file]
                set file [getdistname $file]
                lappend all_dist_files $file
                if {$distsite != ""} {
                    lappend fetch_urls $distsite $file
                } elseif {[info exists patch_sites]} {
                    lappend fetch_urls patch_sites $file
                } else {
                    lappend fetch_urls master_sites $file
                }
            }
        }
    }
}

# Checks dist files and their tags to assemble url lists for later fetching
proc portfetch::checkdistfiles {urls} {
    global distfiles all_dist_files filespath
    upvar $urls fetch_urls

    if {[info exists distfiles]} {
        foreach file $distfiles {
            if {![file exists "${filespath}/${file}"]} {
                set distsite [getdisttag $file]
                set file [getdistname $file]
                lappend all_dist_files $file
                if {$distsite != ""} {
                    lappend fetch_urls $distsite $file
                } else {
                    lappend fetch_urls master_sites $file
                }
            }
        }
    }
}

# returns full path to mirror list file
proc portfetch::get_full_mirror_sites_path {} {
    global mirror_sites.listfile mirror_sites.listpath porturl
    return [getportresourcepath $porturl [file join ${mirror_sites.listpath} ${mirror_sites.listfile}]]
}

# Perform the full checksites/checkpatchfiles/checkdistfiles sequence.
# This method is used by distcheck target.
proc portfetch::checkfiles {urls} {
    global global_mirror_site fallback_mirror_site
    upvar $urls fetch_urls

    checksites [list patch_sites [list $global_mirror_site $fallback_mirror_site PATCH_SITE_LOCAL] \
                master_sites [list $global_mirror_site $fallback_mirror_site MASTER_SITE_LOCAL]] \
               [get_full_mirror_sites_path]
    checkpatchfiles fetch_urls
    checkdistfiles fetch_urls
}

# Perform a bzr fetch
proc portfetch::bzrfetch {args} {
    if {[catch {command_exec bzr "" "2>&1"} result]} {
        return -code error [msgcat::mc "Bazaar checkout failed"]
    }

    if {[info exists patchfiles]} {
        return [portfetch::fetchfiles]
    }

    return 0
}

# Perform a CVS login and fetch, storing the CVS login
# information in a custom .cvspass file
proc portfetch::cvsfetch {args} {
    global workpath cvs.env cvs.cmd cvs.args cvs.post_args
    global cvs.root cvs.date cvs.tag cvs.method cvs.password
    global patch_sites patchfiles filespath

    set cvs.args "${cvs.method} ${cvs.args}"
    if {${cvs.method} == "export" && ![string length ${cvs.tag}] && ![string length ${cvs.date}]} {
        set cvs.tag "HEAD"
    }
    if {[string length ${cvs.tag}]} {
        set cvs.args "${cvs.args} -r ${cvs.tag}"
    }

    if {[string length ${cvs.date}]} {
        set cvs.args "${cvs.args} -D ${cvs.date}"
    }

    if {[regexp ^:pserver: ${cvs.root}]} {
        set savecmd ${cvs.cmd}
        set saveargs ${cvs.args}
        set savepost_args ${cvs.post_args}
        set cvs.cmd "echo ${cvs.password} | ${cvs.cmd}"
        set cvs.args login
        set cvs.post_args ""
        if {[catch {command_exec cvs -notty "" "2>&1"} result]} {
            return -code error [msgcat::mc "CVS login failed"]
        }
        set cvs.cmd ${savecmd}
        set cvs.args ${saveargs}
        set cvs.post_args ${savepost_args}
    } else {
        set env(CVS_RSH) ssh
    }

    if {[catch {command_exec cvs "" "2>&1"} result]} {
        return -code error [msgcat::mc "CVS check out failed"]
    }

    if {[info exists patchfiles]} {
        return [portfetch::fetchfiles]
    }
    return 0
}

# Perform an svn fetch
proc portfetch::svnfetch {args} {
    global svn.args svn.method svn.revision svn.url

    if {[regexp {\s} ${svn.url}]} {
        return -code error [msgcat::mc "Subversion URL cannot contain whitespace"]
    }

    if {[string length ${svn.revision}]} {
        append svn.url "@${svn.revision}"
    }
    set svn.args "${svn.method} ${svn.args} ${svn.url}"

    if {[catch {command_exec svn "" "2>&1"} result]} {
        return -code error [msgcat::mc "Subversion check out failed"]
    }

    if {[info exists patchfiles]} {
        return [portfetch::fetchfiles]
    }

    return 0
}

# Perform a git fetch
proc portfetch::gitfetch {args} {
    global worksrcpath
    global git.url git.branch git.sha1 git.cmd

    set options "-q"
    if {[string length ${git.branch}] == 0} {
        # if we're just using HEAD, we can make a shallow repo
        set options "$options --depth=1"
    }
    set cmdstring "${git.cmd} clone $options ${git.url} ${worksrcpath} 2>&1"
    ui_debug "Executing: $cmdstring"
    if {[catch {system $cmdstring} result]} {
        return -code error [msgcat::mc "Git clone failed"]
    }

    if {[string length ${git.branch}] > 0} {
        set env "GIT_DIR=${worksrcpath}/.git GIT_WORK_TREE=${worksrcpath}"
        set cmdstring "$env ${git.cmd} checkout -q ${git.branch} 2>&1"
        ui_debug "Executing $cmdstring"
        if {[catch {system $cmdstring} result]} {
            return -code error [msgcat::mc "Git checkout failed"]
        }
    }

    if {[info exists patchfiles]} {
        return [portfetch::fetchfiles]
    }

    return 0
}

# Perform a mercurial fetch.
proc portfetch::hgfetch {args} {
    global worksrcpath prefix_frozen
    global hg.url hg.tag hg.cmd

    set cmdstring "${hg.cmd} clone --rev ${hg.tag} ${hg.url} ${worksrcpath} 2>&1"
    ui_debug "Executing: $cmdstring"
    if {[catch {system $cmdstring} result]} {
        return -code error [msgcat::mc "Mercurial clone failed"]
    }

    if {[info exists patchfiles]} {
        return [portfetch::fetchfiles]
    }

    return 0
}

# Perform a standard fetch, assembling fetch urls from
# the listed url variable and associated distfile
proc portfetch::fetchfiles {args} {
    global distpath all_dist_files UI_PREFIX
    global fetch.user fetch.password fetch.use_epsv fetch.ignore_sslcert fetch.remote_time
    global fallback_mirror_site portverbose usealtworkpath altprefix
    variable fetch_urls
    variable urlmap

    set fetch_options {}
    if {[string length ${fetch.user}] || [string length ${fetch.password}]} {
        lappend fetch_options -u
        lappend fetch_options "${fetch.user}:${fetch.password}"
    }
    if {${fetch.use_epsv} != "yes"} {
        lappend fetch_options "--disable-epsv"
    }
    if {${fetch.ignore_sslcert} != "no"} {
        lappend fetch_options "--ignore-ssl-cert"
    }
    if {${fetch.remote_time} != "no"} {
        lappend fetch_options "--remote-time"
    }
    if {$portverbose == "yes"} {
        lappend fetch_options "-v"
    }
    set sorted no

    foreach {url_var distfile} $fetch_urls {
        if {![file isfile "${distpath}/${distfile}"]} {
            ui_info "$UI_PREFIX [format [msgcat::mc "%s doesn't seem to exist in %s"] $distfile $distpath]"
            if {![file writable $distpath]} {
                return -code error [format [msgcat::mc "%s must be writable"] $distpath]
            }
            if {!$usealtworkpath && [file isfile ${altprefix}${distpath}/${distfile}]} {
                if {[catch {file link -hard "${distpath}/${distfile}" "${altprefix}${distpath}/${distfile}"}]} {
                    ui_debug "failed to hardlink ${distfile} into distpath, copying instead"
                    file copy "${altprefix}${distpath}/${distfile}" "${distpath}/${distfile}"
                }
                ui_info "Found $distfile in ${altprefix}${distpath}"
                continue
            }
            if {!$sorted} {
                sortsites fetch_urls [mirror_sites $fallback_mirror_site {} {} [get_full_mirror_sites_path]] master_sites
                set sorted yes
            }
            if {![info exists urlmap($url_var)]} {
                ui_error [format [msgcat::mc "No defined site for tag: %s, using master_sites"] $url_var]
                set urlmap($url_var) $urlmap(master_sites)
            }
            unset -nocomplain fetched
            foreach site $urlmap($url_var) {
                ui_notice "$UI_PREFIX [format [msgcat::mc "Attempting to fetch %s from %s"] $distfile $site]"
                set file_url [portfetch::assemble_url $site $distfile]
                if {![catch {eval curl fetch $fetch_options {$file_url} {"${distpath}/${distfile}.TMP"}} result] &&
                    ![catch {file rename -force "${distpath}/${distfile}.TMP" "${distpath}/${distfile}"} result]} {
                    set fetched 1
                    break
                } else {
                    ui_debug "[msgcat::mc "Fetching failed:"]: $result"
                    file delete -force "${distpath}/${distfile}.TMP"
                }
            }
            if {![info exists fetched]} {
                return -code error [msgcat::mc "fetch failed"]
            }
        }
    }
    return 0
}

# Utility function to delete fetched files.
proc portfetch::fetch_deletefiles {args} {
    global distpath
    variable fetch_urls
    foreach {url_var distfile} $fetch_urls {
        if {[file isfile $distpath/$distfile]} {
            file delete -force "${distpath}/${distfile}"
        }
    }
}

# Utility function to add files to a list of fetched files.
proc portfetch::fetch_addfilestomap {filemapname} {
    global distpath $filemapname
    variable fetch_urls
    foreach {url_var distfile} $fetch_urls {
        if {[file isfile $distpath/$distfile]} {
            filemap set $filemapname $distpath/$distfile 1
        }
    }
}

# Initialize fetch target and call checkfiles.
proc portfetch::fetch_init {args} {
    variable fetch_urls

    portfetch::checkfiles fetch_urls
}

proc portfetch::fetch_start {args} {
    global UI_PREFIX subport distpath

    ui_notice "$UI_PREFIX [format [msgcat::mc "Fetching %s"] $subport]"

    # create and chown $distpath
    if {![file isdirectory $distpath]} {
        if {[catch {file mkdir $distpath} result]} {
            elevateToRoot "fetch"
            set elevated yes
            if {[catch {file mkdir $distpath} result]} {
                return -code error [format [msgcat::mc "Unable to create distribution files path: %s"] $result]
            }
        }
    }
    chownAsRoot $distpath
    if {[info exists elevated] && $elevated == yes} {
        dropPrivileges
    }
}

# Main fetch routine
# If all_dist_files is not populated and $fetch.type == standard, then
# there are no files to download. Otherwise, either do a cvs checkout
# or call the standard fetchfiles procedure
proc portfetch::fetch_main {args} {
    global all_dist_files fetch.type

    # Check for files, download if necessary
    if {![info exists all_dist_files] && "${fetch.type}" == "standard"} {
        return 0
    }

    # Fetch the files
    switch -- "${fetch.type}" {
        bzr     { return [bzrfetch] }
        cvs     { return [cvsfetch] }
        svn     { return [svnfetch] }
        git     { return [gitfetch] }
        hg      { return [hgfetch] }
        standard -
        default { return [portfetch::fetchfiles] }
    }
}
