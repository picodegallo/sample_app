# New ports collection makefile for:	MacPorts
# Date created:		25 June 2007
# Whom:			afb
#
# $FreeBSD$
#

PORTNAME=	macports
PORTVERSION=	2.0.4
CATEGORIES=	sysutils
MASTER_SITES=	http://distfiles.macports.org/MacPorts/
DISTNAME=	MacPorts-${PORTVERSION}

MAINTAINER=	afb@macports.org
COMMENT=	MacPorts allows installing software on Mac OS X (and other platforms)

RUN_DEPENDS=	rsync:${PORTSDIR}/net/rsync \
		ginstall:${PORTSDIR}/sysutils/coreutils \
		gtar:${PORTSDIR}/archivers/gtar \
		gmake:${PORTSDIR}/devel/gmake
LIB_DEPENDS=	tcl85:${PORTSDIR}/lang/tcl85-thread \
		curl:${PORTSDIR}/ftp/curl \
		sqlite3:${PORTSDIR}/databases/sqlite3
BUILD_DEPENDS=	${LOCALBASE}/lib/thread2.6.5:${PORTSDIR}/devel/tclthread \
		bash:${PORTSDIR}/shells/bash

# X11 is only "recommended"

USE_BZIP2=	yes
USE_GMAKE=	yes
#USE_XLIB=	yes
USE_GNUSTEP=	yes

USE_GNUSTEP_BASE=	yes
USE_GNUSTEP_CONFIGURE=	yes
USE_GNUSTEP_BUILD=	yes
USE_GNUSTEP_INSTALL=	yes

PREFIX?=	/opt/local
MTREE_FILE=	${WRKSRC}/doc/prefix.mtree

GNU_CONFIGURE=	yes
CFLAGS+=	-DPIC -fPIC
CONFIGURE_ARGS+=--with-tcl=${LOCALBASE}/lib/tcl8.5 \
		--with-tclinclude=${LOCALBASE}/include/tcl8.5 \
		--without-included-tclthread --without-included-sqlite3 \
		--with-objc-runtime=GNU --with-objc-foundation=GNUstep
CONFIGURE_ENV=	RSYNC=${LOCALBASE}/bin/rsync \
		TCLSH=${LOCALBASE}/bin/tclsh8.5-threads \
		GNUTAR=${LOCALBASE}/bin/gtar \
		GNUMAKE=${LOCALBASE}/bin/gmake \
		OBJC="${CC}" OBJCFLAGS="${CFLAGS}"

pre-configure:
	@# foundation.m4 is somewhat bashist (MacPorts Bug #12252)
	@${REINPLACE_CMD} -e 's|#! /bin/sh|#!/usr/bin/env bash|' ${WRKSRC}/configure
post-configure:
	@# Makefile only works with GNU make (MacPorts Bug #12247)
	@${LN} -s Makefile ${WRKSRC}/GNUmakefile

post-install:
	@# move tcl from /usr/local, to /opt/local (for packaging)
	${RM} -rf ${PREFIX}/share/macports/Tcl/macports1.0
	${MKDIR} ${PREFIX}/share/macports/Tcl
	test -L ${LOCALBASE}/lib/tcl8.5/macports1.0 || \
	${MV} ${LOCALBASE}/lib/tcl8.5/macports1.0 \
	      ${PREFIX}/share/macports/Tcl/macports1.0
	test -L ${LOCALBASE}/lib/tcl8.5/macports1.0 || \
	${LN} -s ${PREFIX}/share/macports/Tcl/macports1.0 \
	         ${LOCALBASE}/lib/tcl8.5/macports1.0

test: build
	${GMAKE} -C ${WRKSRC} test

# MacPorts mtree demands ${prefix}/share/man
MANPREFIX=	${PREFIX}/share
MANCOMPRESSED=	yes

MAN1=		port.1
MAN5=		macports.conf.5
MAN7=		portfile.7 portgroup.7 porthier.7 portstyle.7

.include <bsd.port.mk>
