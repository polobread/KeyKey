PORTNAME=	fcitx5-keykey
DISTVERSION=	1.3.1
CATEGORIES=	chinese textproc

MAINTAINER=	polobread@yahoo.com.tw
COMMENT=	Chichi77 KeyKey input methods for Fcitx 5
WWW=		https://github.com/polobread/KeyKey

LICENSE=	BSD3CLAUSE MIT
LICENSE_COMB=	multi
LICENSE_FILE_BSD3CLAUSE=	${WRKSRC}/LICENSE.txt
LICENSE_FILE_MIT=	${WRKSRC}/LICENSES/MIT.txt

LIB_DEPENDS=	libFcitx5Core.so:textproc/fcitx5 \
		libcanberra.so:audio/libcanberra \
		libsqlite3.so:databases/sqlite3
RUN_DEPENDS=	fcitx5:textproc/fcitx5

USES=		cmake compiler:c++17-lang iconv pkgconfig python:build
USE_GITHUB=	yes
GH_ACCOUNT=	polobread
GH_PROJECT=	KeyKey
GH_TAGNAME=	v${DISTVERSION}

CMAKE_SOURCE_PATH=	${WRKSRC}/Source/Loaders/FreeBSD-IME
CMAKE_ARGS=	-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_INSTALL_MANDIR=share/man
CMAKE_ON=	KEYKEY_BUILD_FCITX5 BUILD_TESTING
TEST_TARGET=	test

.include <bsd.port.mk>
