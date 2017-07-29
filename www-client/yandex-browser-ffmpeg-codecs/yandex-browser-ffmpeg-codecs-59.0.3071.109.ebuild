# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6

inherit eutils unpacker

KEYWORDS="-* ~amd64"
DESCRIPTION="Multi-threaded ffmpeg codecs needed for the HTML5 <audio> and <video> tags"
HOMEPAGE="http://www.chromium.org/Home"
SLOT="0"
LICENSE="BSD"
RESTRICT="bindist strip"

DEBIAN_REVISION="0ubuntu0.17.04.1360"
_FULL_VERSION="${PV}-${DEBIAN_REVISION}"
URI="http://security.ubuntu.com/ubuntu/pool/universe/c/chromium-browser"
SRC_URI="amd64? ( ${URI}/chromium-codecs-ffmpeg-extra_${_FULL_VERSION}_amd64.deb )"

RDEPEND="www-client/yandex-browser-beta"

src_unpack() {
	mkdir ${P}
	cd ${P}
	unpack_deb ${A}
}

src_install() {
	insinto /opt/yandex/browser-beta
	doins "${WORKDIR}/${P}/usr/lib/chromium-browser/libffmpeg.so"
}
