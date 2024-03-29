# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:filetype=tcl:et:sw=4:ts=4:sts=4
# portpkg.tcl
# $Id: portpkg.tcl 90059 2012-02-20 10:40:37Z jmr@macports.org $
#
# Copyright (c) 2005, 2007 - 2011 The MacPorts Project
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

package provide portpkg 1.0
package require portutil 1.0

set org.macports.pkg [target_new org.macports.pkg portpkg::pkg_main]
target_runtype ${org.macports.pkg} always
target_provides ${org.macports.pkg} pkg
target_requires ${org.macports.pkg} archivefetch unarchive destroot

namespace eval portpkg {
}

# define options
options package.type package.destpath package.flat

# Set defaults
default package.destpath {${workpath}}
default package.flat     false

set_ui_prefix

proc portpkg::pkg_main {args} {
    global subport version revision package.type package.destpath package.flat UI_PREFIX

    ui_msg "$UI_PREFIX [format [msgcat::mc "Creating pkg for %s-%s"] ${subport} ${version}]"

    if {[getuid] == 0 && [geteuid] != 0} {
        elevateToRoot "pkg"
    }

    return [package_pkg $subport $version $revision]
}

proc portpkg::package_pkg {portname portversion portrevision} {
    global UI_PREFIX portdbpath destpath workpath prefix description \
    package.destpath package.flat long_description homepage portpath porturl \
    os.version os.major xcodeversion packagemaker_path

    set pkgpath ${package.destpath}/${portname}-${portversion}.pkg

    if {[file readable $pkgpath] && ([file mtime ${pkgpath}] >= [file mtime ${portpath}/Portfile])} {
        ui_msg "$UI_PREFIX [format [msgcat::mc "Package for %s-%s is up-to-date"] ${portname} ${portversion}]"
        return 0
    }

    if {![info exists packagemaker_path]} {
        if {[vercmp $xcodeversion 4.3] >= 0} {
            set packagemaker_path /Applications/PackageMaker.app
            if {![file exists $packagemaker_path]} {
                ui_warn "PackageMaker.app not found; you may need to install it or set packagemaker_path in macports.conf"
            }
        } else {
            set packagemaker_path "[option developer_dir]/Applications/Utilities/PackageMaker.app"
        }
    }
    set packagemaker "${packagemaker_path}/Contents/MacOS/PackageMaker"
    if ([file exists "$packagemaker"]) {
        set resourcepath ${workpath}/pkg_resources
    } else {
        set resourcepath "${pkgpath}/Contents/Resources"
    }

    set language "English"
    file mkdir "${resourcepath}/${language}.lproj"
    file attributes "${resourcepath}/${language}.lproj" -permissions 0755
	
    # long_description, description, or homepage may not exist
    foreach variable {long_description description homepage} {
        if {![info exists $variable]} {
            set pkg_$variable ""
        } else {
            set pkg_$variable [set $variable]
        }
    }
    write_welcome_html ${resourcepath}/${language}.lproj/Welcome.html $portname $portversion $pkg_long_description $pkg_description $pkg_homepage
    file copy -force -- [getportresourcepath $porturl "port1.0/package/background.tiff"] ${resourcepath}/${language}.lproj/background.tiff

    foreach dir {etc var tmp} {
        if ([file exists "${destpath}/$dir"]) {
            # certain toplevel directories really are symlinks. leaving them as directories make pax lose the symlinks. that's bad.
            file mkdir "${destpath}/private/${dir}"
            eval file rename [glob ${destpath}/${dir}/*] "${destpath}/private/${dir}"
            delete "${destpath}/${dir}"
        }
    }

    if ([file exists "$packagemaker"]) {

        ui_debug "Calling $packagemaker for $portname pkg"
        if {${os.major} >= 9} {
            if {${package.flat}} {
                set pkgtarget "10.5"
                set pkgresources ""
                set infofile "${workpath}/PackageInfo"
                write_package_info ${workpath}/PackageInfo $portname $portversion $portrevision
            } else {
                set pkgtarget "10.3"
                set pkgresources " --resources ${resourcepath} --title \"$portname-$portversion\""
                set infofile "${workpath}/Info.plist"
                write_info_plist ${workpath}/Info.plist $portname $portversion $portrevision
            }
            set cmdline "PMResourceLocale=${language} $packagemaker -AppleLanguages \"(${language})\" --root ${destpath} --out ${pkgpath} ${pkgresources} --info $infofile --target $pkgtarget --domain system --id org.macports.$portname"
            if {${os.major} >= 10} {
                append cmdline " --no-relocate"
            }
            ui_debug "Running command line: $cmdline"
            system $cmdline
        } else {
            write_info_plist ${workpath}/Info.plist $portname $portversion $portrevision
            write_description_plist ${workpath}/Description.plist $portname $portversion $description
            system "$packagemaker -build -f ${destpath} -p ${pkgpath} -r ${resourcepath} -i ${workpath}/Info.plist -d ${workpath}/Description.plist"
        }

        file delete ${workpath}/Info.plist
        file delete ${workpath}/PackageInfo
        file delete ${workpath}/Description.plist
        file delete -force ${workpath}/pkg_resources

    } else {

        write_PkgInfo ${pkgpath}/Contents/PkgInfo
        write_info_plist ${pkgpath}/Contents/Info.plist $portname $portversion $portrevision

        system "[findBinary mkbom $portutil::autoconf::mkbom_path] ${destpath} ${pkgpath}/Contents/Archive.bom"
        system "cd ${destpath} && [findBinary pax $portutil::autoconf::pax_path] -x [findBinary cpio $portutil::autoconf::cpio_path] -w -z . > ${pkgpath}/Contents/Archive.pax.gz"

        write_description_plist ${resourcepath}/Description.plist $portname $portversion $description
        write_sizes_file ${resourcepath}/Archive.sizes ${portname} ${portversion} ${pkgpath} ${destpath}

    }

    foreach dir {etc var tmp} {
        if ([file exists "${destpath}/private/$dir"]) {
            # restore any directories that were moved, to avoid confusing the rest of the ports system.
            file rename ${destpath}/private/$dir ${destpath}/$dir
        }
    }
    catch {file delete ${destpath}/private}

    return 0
}

proc portpkg::write_PkgInfo {infofile} {
    set infofd [open ${infofile} w+]
    puts $infofd "pmkrpkg1"
    close $infofd
}

proc portpkg::xml_escape {s} {
    regsub -all {&} $s {\&amp;} s
    regsub -all {<} $s {\&lt;} s
    regsub -all {>} $s {\&gt;} s
    return $s
}

proc portpkg::write_info_plist {infofile portname portversion portrevision} {
    set portname [xml_escape $portname]
    set portversion [xml_escape $portversion]
    set portrevision [xml_escape $portrevision]

    set infofd [open ${infofile} w+]
    puts $infofd {<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    }
    puts $infofd "<dict>
    <key>CFBundleGetInfoString</key>
    <string>${portname} ${portversion}</string>
    <key>CFBundleIdentifier</key>
    <string>org.macports.${portname}</string>
    <key>CFBundleName</key>
    <string>${portname}</string>
    <key>CFBundleShortVersionString</key>
    <string>${portversion}</string>
    <key>IFMajorVersion</key>
    <integer>${portrevision}</integer>
    <key>IFMinorVersion</key>
    <integer>0</integer>
    <key>IFPkgFlagAllowBackRev</key>
    <true/>
    <key>IFPkgFlagAuthorizationAction</key>
    <string>RootAuthorization</string>
    <key>IFPkgFlagDefaultLocation</key>
    <string>/</string>
    <key>IFPkgFlagInstallFat</key>
    <false/>
    <key>IFPkgFlagIsRequired</key>
    <false/>
    <key>IFPkgFlagRelocatable</key>
    <false/>
    <key>IFPkgFlagRestartAction</key>
    <string>NoRestart</string>
    <key>IFPkgFlagRootVolumeOnly</key>
    <true/>
    <key>IFPkgFlagUpdateInstalledLanguages</key>
    <false/>
    <key>IFPkgFormatVersion</key>
    <real>0.10000000149011612</real>
</dict>
</plist>"
    close $infofd
}

proc portpkg::write_description_plist {infofile portname portversion description} {
    set portname [xml_escape $portname]
    set portversion [xml_escape $portversion]
    set description [xml_escape $description]

    set infofd [open ${infofile} w+]
    puts $infofd {<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    }
    puts $infofd "<dict>
    <key>IFPkgDescriptionDeleteWarning</key>
    <string></string>
    <key>IFPkgDescriptionDescription</key>
    <string>${description}</string>
    <key>IFPkgDescriptionTitle</key>
    <string>${portname}</string>
    <key>IFPkgDescriptionVersion</key>
    <string>${portversion}</string>
</dict>
</plist>"
    close $infofd
}

proc portpkg::write_welcome_html {filename portname portversion long_description description homepage} {
    set fd [open ${filename} w+]
    if {$long_description == ""} {
        set long_description $description
    }

    set portname [xml_escape $portname]
    set portversion [xml_escape $portversion]
    set long_description [xml_escape $long_description]
    set description [xml_escape $description]
    set homepage [xml_escape $homepage]
	
    puts $fd "
<html lang=\"en\">
<head>
	<meta http-equiv=\"content-type\" content=\"text/html; charset=iso-8859-1\">
	<title>Install ${portname}</title>
</head>
<body>
<font face=\"Helvetica\"><b>Welcome to the ${portname} for Mac OS X Installer</b></font>
<p>
<font face=\"Helvetica\">${long_description}</font>
<p>"

    if {$homepage != ""} {
        puts $fd "<font face=\"Helvetica\"><a href=\"${homepage}\">${homepage}</a></font><p>"
    }

    puts $fd "<font face=\"Helvetica\">This installer guides you through the steps necessary to install ${portname} ${portversion} for Mac OS X. To get started, click Continue.</font>
</body>
</html>"

    close $fd
}

proc portpkg::write_sizes_file {sizesfile portname portversion pkgpath destpath} {
    
    if {[catch {set numFiles [llength [split [exec [findBinary lsbom $portutil::autoconf::lsbom_path] -s ${pkgpath}/Contents/Archive.bom] "\n"]]} result]} {
        return -code error [format [msgcat::mc "Reading package bom failed: %s"] $result]
    }
    if {[catch {set compressedSize [expr [dirSize ${pkgpath}] / 1024]} result]} {
        return -code error [format [msgcat::mc "Error determining compressed size: %s"] $result]
    }
    if {[catch {set installedSize [expr [dirSize ${destpath}] / 1024]} result]} {
        return -code error [format [msgcat::mc "Error determining installed size: %s"] $result]
    }
    if {[catch {set infoSize [file size ${pkgpath}/Contents/Info.plist]} result]} {
       return -code error [format [msgcat::mc "Error determining plist file size: %s"] $result]
    }
    if {[catch {set bomSize [file size ${pkgpath}/Contents/Archive.bom]} result]} {
        return -code error [format [msgcat::mc "Error determining bom file size: %s"] $result]
    }
    incr installedSize $infoSize
    incr installedSize $bomSize
	
    set fd [open ${sizesfile} w+]
    puts $fd "NumFiles $numFiles
InstalledSize $installedSize
CompressedSize $compressedSize"
    close $fd
}

proc portpkg::write_package_info {infofile portname portversion portrevision} {
    set portname [xml_escape $portname]
    set portversion [xml_escape $portversion]
    set portrevision [xml_escape $portrevision]

    set infofd [open ${infofile} w+]
    puts $infofd "
<pkg-info install-location=\"/\" relocatable=\"false\" auth=\"root\">
</pkg-info>"
    close $infofd
}
