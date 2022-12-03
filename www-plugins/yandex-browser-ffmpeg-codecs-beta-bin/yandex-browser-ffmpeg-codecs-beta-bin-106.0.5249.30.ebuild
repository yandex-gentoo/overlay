# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker

KEYWORDS="~amd64"
DESCRIPTION="Multi-threaded ffmpeg codecs needed for the HTML5 <audio> and <video> tags"
HOMEPAGE="http://www.chromium.org/Home"
SLOT="0"
LICENSE="BSD"
RESTRICT="bindist strip mirror"

DEBIAN_REVISION="2ubuntu0.18.04"
_FULL_VERSION="${PV}-${DEBIAN_REVISION}"
BASE_URI="https://launchpadlibrarian.net/623257277/"
SRC_URI="
	amd64? ( ${BASE_URI}/chromium-codecs-ffmpeg-extra_${_FULL_VERSION}_amd64.deb )
"
S="${WORKDIR}"

src_unpack() {
	unpack_deb ${A}
}

src_install() {
	insinto /opt/yandex/browser-beta
	doins usr/lib/chromium-browser/libffmpeg.so
}
