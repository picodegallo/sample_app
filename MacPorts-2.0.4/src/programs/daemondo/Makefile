# $Id: Makefile.in 54794 2009-08-02 05:17:03Z toby@macports.org $

top_srcdir = ../../..

include ${top_srcdir}/Mk/macports.autoconf.mk

datarootdir=	${prefix}/share
mandir=		${datarootdir}/man
mandircat8=	${mandir}/cat8

CFLAGS_QUICHEEATERS	= -W -Wall
CPPFLAGS	+= -I../..
SRCS		= main.c
OBJS		= main.o
LIBS		= -framework CoreFoundation \
			  -framework SystemConfiguration \
			  -framework IOKit
PROGRAM		= build/daemondo

all: daemondo

daemondo: mkdirs ${PROGRAM}

${PROGRAM}: ${OBJS}
	${CC} ${CFLAGS} -o ${PROGRAM} ${LIBS} ${OBJS}

mkdirs:
	mkdir -p build

clean:
	rm -Rf build ${PROGRAM} ${OBJS}

distclean: clean
	rm -f Makefile

install: daemondo
	${INSTALL} -o ${DSTUSR} -g ${DSTGRP} -m 555 ${PROGRAM} ${DESTDIR}${bindir}

test:
