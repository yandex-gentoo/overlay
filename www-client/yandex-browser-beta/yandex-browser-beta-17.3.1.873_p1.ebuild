# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6
CHROMIUM_LANGS="cs de en-US es fr it ja pt-BR pt-PT ru tr uk zh-CN zh-TW"
inherit chromium-2 unpacker pax-utils

RESTRICT="mirror"

MY_PV="${PV/_p/-}"

DESCRIPTION="The web browser from Yandex"
HOMEPAGE="http://browser.yandex.ru/beta/"
LICENSE="Yandex-EULA"
SLOT="0"
SRC_URI="
	amd64? ( http://repo.yandex.ru/yandex-browser/deb/pool/main/y/yandex-browser-beta/yandex-browser-beta_${MY_PV}_amd64.deb -> ${P}.deb )
"
KEYWORDS="~amd64"

RDEPEND="
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	>=dev-libs/openssl-1.0.1:0
	gnome-base/gconf:2
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	net-misc/curl
	net-print/cups
	sys-apps/dbus
	sys-libs/libcap
	virtual/libudev
	x11-libs/cairo
	x11-libs/gdk-pixbuf
	x11-libs/gtk+:2
	x11-libs/libX11
	x11-libs/libXScrnSaver
	x11-libs/libXcomposite
	x11-libs/libXcursor
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXi
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/libXtst
	x11-libs/pango[X]
	x11-misc/xdg-utils
"

QA_PREBUILT="*"
S=${WORKDIR}
YANDEX_HOME="opt/${PN/-//}"

pkg_setup() {
	chromium_suid_sandbox_check_kernel_config
}

src_unpack() {
	unpack_deb ${A}
}

src_prepare() {
	rm usr/bin/${PN} || die

	rm -r etc || die

	rm -r "${YANDEX_HOME}/cron" || die

	mv usr/share/doc/${PN} usr/share/doc/${PF} || die

	pushd "${YANDEX_HOME}/locales" > /dev/null || die
	chromium_remove_language_paks
	popd > /dev/null || die

	default

	sed -r \
		-e 's|\[(NewWindow)|\[X-\1|g' \
		-e 's|\[(NewIncognito)|\[X-\1|g' \
		-e 's|^TargetEnvironment|X-&|g' \
		-i usr/share/applications/${PN}.desktop || die
}

src_install() {
	# FIXME: XXX: Dirty kludge to avoid portage insecure SUIDs protection
	chmod 0500 "${YANDEX_HOME}/yandex_browser-sandbox"

	mv * "${D}" || die
	dodir /usr/$(get_libdir)/${PN}/lib
	make_wrapper "${PN}" "./${PN}" "/${YANDEX_HOME}" "/usr/$(get_libdir)/${PN}/lib"
	dosym /usr/$(get_libdir)/libudev.so /usr/$(get_libdir)/${PN}/lib/libudev.so.0

	for icon in "${D}/${YANDEX_HOME}/product_logo_"*.png; do
		size="${icon##*/product_logo_}"
		size=${size%.png}
		dodir "/usr/share/icons/hicolor/${size}x${size}/apps"
		newicon -s "${size}" "$icon" "yandex-browser-beta.png"
	done

	fowners root:root "/${YANDEX_HOME}/yandex_browser-sandbox"
	pax-mark m "${ED}${YANDEX_HOME}/yandex_browser-sandbox"
}

pkg_postinst() {
	eerror "Hello! This is a BIG RED notification about insecure state of this package."
	eerror "Please, keep calm. It is not a fatal error, which prevent package installation."
	eerror "Actually it is a notification about kludges to avoid it and make package to install"
	eerror "in any way, because you will not be able to use your preferred browser otherwise."
	eerror ""
	eerror "The situation is in fact that SUID sandbox helper binary in ${PN}, is built with DT_RPATH='\$ORIGIN/.'"
	eerror "This means, it is VERY vulnerable to attacks through libraries preloading."
	eerror ""
	eerror "In particular, it can be circumstances when attacker can force it"
	eerror "to load libraries from controlled directory and so take control over it."
	eerror ""
	eerror "This is the bug in compilation (link time) process and, since ${PN} is proprietary software,"
	eerror "this can't be fixed in any way except reporting this upstream."
	eerror "But, since upstream has no public bugtracker, it is only users (you) who can report this"
	eerror "and force them to fix that."
	eerror ""
	eerror "For now we can only make kludges to avoid portage protection system and get it installed."
	eerror "So, be notified, that since now you have a big security hole in your system."

	chmod 4711 "/${YANDEX_HOME}/yandex_browser-sandbox"
}
