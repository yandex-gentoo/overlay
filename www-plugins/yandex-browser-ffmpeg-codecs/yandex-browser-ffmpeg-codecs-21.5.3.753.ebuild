# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7
PYTHON_COMPAT=( python2_7 )
MY_PV="90.0.4430.72"
inherit check-reqs chromium-2 flag-o-matic ninja-utils python-any-r1 toolchain-funcs

RESTRICT="bindist mirror"
DESCRIPTION="Multi-threaded ffmpeg codecs needed for the HTML5 <audio> and <video> tags"
HOMEPAGE="http://www.chromium.org/Home"
HOMEPAGE="https://chromium.org/"
#PATCHSET_NAME="chromium-90-patchset-7"
SRC_URI="
	https://commondatastorage.googleapis.com/chromium-browser-official/chromium-${MY_PV}.tar.xz -> ${P}.tar.xz
	http://gpo.ws54.tk/gentoo-distfiles/${P}.tar.xz
"
#	https://github.com/stha09/chromium-patches/releases/download/${PATCHSET_NAME}/${PATCHSET_NAME}.tar.xz

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+component-build +proprietary-codecs pulseaudio"

COMMON_DEPEND="
	app-arch/bzip2:=
	dev-libs/expat:=
	dev-libs/glib:2
	>=dev-libs/libxml2-2.9.4-r3:=[icu]
	dev-libs/libxslt:=
	dev-libs/nspr:=
	>=dev-libs/re2-0.2019.08.01:=
	>=media-libs/alsa-lib-1.0.19:=
	media-libs/fontconfig:=
	media-libs/freetype:=
	>=media-libs/harfbuzz-2.4.0:0=[icu(-)]
	media-libs/libjpeg-turbo:=
	media-libs/libpng:=
	>=media-libs/openh264-1.6.0:=
	pulseaudio? ( media-sound/pulseaudio:= )
	sys-apps/dbus:=
	virtual/udev
	app-arch/snappy:=
	media-libs/flac:=
	>=media-libs/libwebp-0.4.0:=
	sys-libs/zlib:=[minizip]
"

RDEPEND="${COMMON_DEPEND}
	sys-libs/glibc
"

DEPEND="${COMMON_DEPEND}
	>=app-arch/gzip-1.7
	dev-lang/perl
	>=dev-libs/nss-3.26:=
	>=dev-util/gn-0.1807
	>=dev-util/gperf-3.0.3
	>=dev-util/ninja-1.7.2
	dev-vcs/git
	>=net-libs/nodejs-7.6.0[inspector]
	sys-apps/hwids[usb(+)]
	>=sys-devel/bison-2.4.3
	sys-apps/pciutils:=
	sys-devel/flex
	virtual/pkgconfig
"

: ${CHROMIUM_FORCE_CLANG=yes}

if [[ ${CHROMIUM_FORCE_CLANG} == yes ]]; then
	DEPEND+=" >=sys-devel/clang-12"
fi

if ! has chromium_pkg_die ${EBUILD_DEATH_HOOKS}; then
	EBUILD_DEATH_HOOKS+=" chromium_pkg_die";
fi

DISABLE_AUTOFORMATTING="yes"

S="${WORKDIR}/chromium-${MY_PV}"
YANDEX_HOME="opt/yandex/browser-beta"

pre_build_checks() {
	# Check build requirements, bug #541816 and bug #471810 .
	CHECKREQS_MEMORY="3G"
	CHECKREQS_DISK_BUILD="6G"
	eshopts_push -s extglob
	if is-flagq '-g?(gdb)?([1-9])'; then
		CHECKREQS_DISK_BUILD="25G"
		if ! use component-build; then
			CHECKREQS_MEMORY="16G"
		fi
	fi
	eshopts_pop
	check-reqs_pkg_setup
}

pkg_pretend() {
	pre_build_checks
}

pkg_setup() {
	pre_build_checks

	# chromium_suid_sandbox_check_kernel_config
}

src_prepare() {
	# Calling this here supports resumption via FEATURES=keepwork
	python_setup

	# Use Python 2
	find -name '*.py' | xargs sed -e 's|env python|&2|g' -e 's|bin/python|&2|g' -i || true

	default

	mkdir -p third_party/node/linux/node-linux-x64/bin || die
	ln -s "${EPREFIX}"/usr/bin/node third_party/node/linux/node-linux-x64/bin/node || die

}

bootstrap_gn() {
	if tc-is-cross-compiler; then
		local -x AR=${BUILD_AR}
		local -x CC=${BUILD_CC}
		local -x CXX=${BUILD_CXX}
		local -x NM=${BUILD_NM}
		local -x CFLAGS=${BUILD_CFLAGS}
		local -x CXXFLAGS=${BUILD_CXXFLAGS}
		local -x LDFLAGS=${BUILD_LDFLAGS}
	fi
	einfo "Building GN..."
#	set -- tools/gn/bootstrap/bootstrap.py -s -v --no-clean
	set -- tools/gn/bootstrap/bootstrap.py -s -v -o ott/Release/gn
	echo "$@"
	"$@" || die
}

src_configure() {
	# Calling this here supports resumption via FEATURES=keepwork
	python_setup

	local myconf_gn=""

	# Make sure the build system will use the right tools, bug #340795.
	tc-export AR CC CXX NM

	if [[ ${CHROMIUM_FORCE_CLANG} == yes ]] && ! tc-is-clang; then
		# Force clang since gcc is pretty broken at the moment.
		CC=${CHOST}-clang
		CXX=${CHOST}-clang++
		strip-unsupported-flags
	fi

	if tc-is-clang; then
		myconf_gn+=" is_clang=true clang_use_chrome_plugins=false"
	else
		myconf_gn+=" is_clang=false"
	fi

	# Define a custom toolchain for GN
	myconf_gn+=" custom_toolchain=\"//build/toolchain/linux/unbundle:default\""

	if tc-is-cross-compiler; then
		tc-export BUILD_{AR,CC,CXX,NM}
		myconf_gn+=" host_toolchain=\"//build/toolchain/linux/unbundle:host\""
		myconf_gn+=" v8_snapshot_toolchain=\"//build/toolchain/linux/unbundle:host\""
	else
		myconf_gn+=" host_toolchain=\"//build/toolchain/linux/unbundle:default\""
	fi

	# GN needs explicit config for Debug/Release as opposed to inferring it from build directory.
	myconf_gn+=" is_debug=false"

	# Component build isn't generally intended for use by end users. It's mostly useful
	# for development and debugging.
	myconf_gn+=" is_component_build=true"

	# https://chromium.googlesource.com/chromium/src/+/lkcr/docs/jumbo.md
	myconf_gn+=" use_jumbo_build=false"

	myconf_gn+=" use_allocator=\"none\""

	# Disable nacl, we can't build without pnacl (http://crbug.com/269560).
	myconf_gn+=" enable_nacl=false enable_nacl_nonsfi=false"

	# Use system-provided libraries.
	# TODO: freetype (https://bugs.chromium.org/p/pdfium/issues/detail?id=733).
	# TODO: use_system_hunspell (upstream changes needed).
	# TODO: use_system_libsrtp (bug #459932).
	# TODO: use_system_protobuf (bug #525560).
	# TODO: use_system_ssl (http://crbug.com/58087).
	# TODO: use_system_sqlite (http://crbug.com/22208).

	## 2018-06-16
	# libevent: https://bugs.gentoo.org/593458
	# local gn_system_libraries=(
	# 	flac
	# 	fontconfig
	# 	freetype
	# 	# Need harfbuzz_from_pkgconfig target
	# 	#harfbuzz-ng
	# 	libdrm
	# 	libjpeg
	# 	libpng
	# 	libwebp
	# 	libxml
	# 	libxslt
	# 	openh264
	# 	re2
	# 	snappy
	# 	yasm
	# 	zlib
	# )
	# if use system-ffmpeg; then
	# 	gn_system_libraries+=( ffmpeg opus )
	# fi
	# if use system-icu; then
	# 	gn_system_libraries+=( icu )
	# fi
	# if use system-libvpx; then
	# 	gn_system_libraries+=( libvpx )
	# fi
	# build/linux/unbundle/replace_gn_files.py --system-libraries "${gn_system_libraries[@]}" || die

	# See dependency logic in third_party/BUILD.gn
	myconf_gn+=" use_system_harfbuzz=true"

	# Optional dependencies.
	myconf_gn+=" enable_hangout_services_extension=false"
	myconf_gn+=" enable_widevine=false"
	myconf_gn+=" use_cups=false"
	myconf_gn+=" use_gconf=false"
	myconf_gn+=" use_gnome_keyring=false"
	myconf_gn+=" use_gtk3=false"
	myconf_gn+=" use_kerberos=false"
	myconf_gn+=" use_pulseaudio=$(usex pulseaudio true false)"

	# TODO??: link_pulseaudio=true for GN.
#	myconf_gn+=" is_clang=false"
	myconf_gn+=" fieldtrial_testing_like_official_build=true"

	# Never use bundled gold binary. Disable gold linker flags for now.
	# Do not use bundled clang.
	# Trying to use gold results in linker crash.
	myconf_gn+=" use_gold=false use_sysroot=false linux_use_bundled_binutils=false use_custom_libcxx=true"

	myconf_gn+=" is_component_build=true "

	ffmpeg_branding="ChromeOS"

	myconf_gn+=" proprietary_codecs=$(usex proprietary-codecs true false)"
	myconf_gn+=" ffmpeg_branding=\"${ffmpeg_branding}\""

	local myarch="$(tc-arch)"
	if [[ $myarch = amd64 ]] ; then
		myconf_gn+=" target_cpu=\"x64\""
		ffmpeg_target_arch=x64
	else
		die "Failed to determine target arch, got '$myarch'."
	fi

	# Make sure that -Werror doesn't get added to CFLAGS by the build system.
	# Depending on GCC version the warnings are different and we don't want
	# the build to fail because of that.
	myconf_gn+=" treat_warnings_as_errors=false"

	# Disable fatal linker warnings, bug 506268.
	myconf_gn+=" fatal_linker_warnings=false"
	# Additional conf
	myconf_gn+=" enable_hevc_demuxing=true"
	myconf_gn+=" use_gio=false"
	myconf_gn+=" symbol_level=0"
	# myconf_gn+=" "

	einfo "Configuring Chromium..."
	set -- gn gen out/Release --args="${myconf_gn}" -v --script-executable=/usr/bin/python2
	echo "$@"
	"$@" || die
}

src_compile() {
	# Calling this here supports resumption via FEATURES=keepwork
	python_setup

	# Even though ninja autodetects number of CPUs, we respect
	# user's options, for debugging with -j 1 or any other reason.
	eninja -C out/Release -v media/ffmpeg
}

src_install() {
	keepdir "${EPREFIX}/${YANDEX_HOME}"
	strip out/Release/libffmpeg.so
	insinto "${YANDEX_HOME}"
	doins out/Release/libffmpeg.so
}
