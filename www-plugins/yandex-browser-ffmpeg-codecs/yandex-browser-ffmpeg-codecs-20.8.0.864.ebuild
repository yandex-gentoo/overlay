# Copyright 1999-2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7
PYTHON_COMPAT=( python2_7 )
MY_PV="84.0.4147.105"
PATCHSET_NAME="chromium-84-patchset-3"

inherit check-reqs chromium-2 desktop flag-o-matic ninja-utils python-any-r1 toolchain-funcs

RESTRICT="bindist mirror"
DESCRIPTION="Multi-threaded ffmpeg codecs needed for the HTML5 <audio> and <video> tags"
HOMEPAGE="http://www.chromium.org/Home"
LICENSE="BSD"
SLOT="0"
SRC_URI="
	https://commondatastorage.googleapis.com/chromium-browser-official/chromium-${MY_PV}.tar.xz -> ${P}.tar.xz
	https://files.pythonhosted.org/packages/ed/7b/bbf89ca71e722b7f9464ebffe4b5ee20a9e5c9a555a56e2d3914bb9119a6/setuptools-44.1.0.zip
	https://github.com/stha09/chromium-patches/releases/download/${PATCHSET_NAME}/${PATCHSET_NAME}.tar.xz
"
KEYWORDS="~amd64"
IUSE="+component-build +proprietary-codecs pulseaudio pic"

COMMON_DEPEND="
	app-arch/bzip2:=
	dev-libs/expat:=
	dev-libs/glib:2
	>=dev-libs/libxml2-2.9.4-r3:=[icu]
	dev-libs/nspr:=
	>=media-libs/alsa-lib-1.0.19:=
	media-libs/fontconfig:=
	media-libs/freetype:=
	>=media-libs/harfbuzz-2.4.0:0=[icu(-)]
	media-libs/libjpeg-turbo:=
	media-libs/libpng:=
	pulseaudio? ( media-sound/pulseaudio:= )
	sys-apps/dbus:=
	virtual/udev
	media-libs/flac:=
	>=media-libs/libwebp-0.4.0:=
	sys-libs/zlib:=[minizip]
"

RDEPEND="${COMMON_DEPEND}
"

DEPEND="${COMMON_DEPEND}
"

BDEPEND="
	${PYTHON_DEPS}
	>=app-arch/gzip-1.7
	app-arch/unzip
	dev-lang/yasm
	dev-lang/perl
	>=dev-libs/nss-3.26:=
	dev-util/gn
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
: ${CHROMIUM_FORCE_CLANG=no}
: ${CHROMIUM_FORCE_LIBCXX=no}

if [[ ${CHROMIUM_FORCE_CLANG} == yes ]]; then
	BDEPEND+=" >=sys-devel/clang-9"
fi

if [[ ${CHROMIUM_FORCE_LIBCXX} == yes ]]; then
	RDEPEND+=" >=sys-libs/libcxx-9"
	DEPEND+=" >=sys-libs/libcxx-9"
else
	COMMON_DEPEND="
		app-arch/snappy:=
		dev-libs/libxslt:=
		>=dev-libs/re2-0.2019.08.01:=
		>=media-libs/openh264-1.6.0:=
	"
	RDEPEND+="${COMMON_DEPEND}"
	DEPEND+="${COMMON_DEPEND}"
fi

if ! has chromium_pkg_die ${EBUILD_DEATH_HOOKS}; then
	EBUILD_DEATH_HOOKS+=" chromium_pkg_die";
fi

DISABLE_AUTOFORMATTING="yes"
PATCHES=(
)

S="${WORKDIR}/chromium-${MY_PV}"
YANDEX_HOME="opt/yandex/browser-beta"

pre_build_checks() {
	# Check build requirements, bug #541816 and bug #471810 .
	CHECKREQS_MEMORY="3G"
	CHECKREQS_DISK_BUILD="7G"
	if is-flagq '-g?(gdb)?([1-9])'; then
		CHECKREQS_DISK_BUILD="25G"
		if ! use component-build; then
			CHECKREQS_MEMORY="16G"
		fi
	fi
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

	eapply "${WORKDIR}/patches"

	# Make xcbgen available to ui/gfx/x/gen_xproto.py running under Python 2
	ln -s "${EPREFIX}"/usr/lib/python3.*/site-packages/xcbgen "${WORKDIR}/"

	default

	mkdir -p third_party/node/linux/node-linux-x64/bin || die
	ln -s "${EPREFIX}"/usr/bin/node third_party/node/linux/node-linux-x64/bin/node || die

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
		if [[ ${CHROMIUM_FORCE_LIBCXX} == yes ]]; then
			die "Compiling with sys-libs/libcxx requires clang."
		fi
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
	myconf_gn+=" enable_nacl=false"

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
	myconf_gn+=" use_gnome_keyring=false"
	myconf_gn+=" use_gtk=false"
	myconf_gn+=" use_kerberos=false"
	myconf_gn+=" use_pulseaudio=$(usex pulseaudio true false)"

	# TODO??: link_pulseaudio=true for GN.
#	myconf_gn+=" is_clang=false"
	myconf_gn+=" fieldtrial_testing_like_official_build=true"

	# Never use bundled gold binary. Disable gold linker flags for now.
	# Do not use bundled clang.
	# Trying to use gold results in linker crash.
	myconf_gn+=" use_gold=false use_sysroot=false use_custom_libcxx=false"

	# Disable forced lld, bug 641556
	myconf_gn+=" use_lld=false"

	ffmpeg_branding="ChromeOS"

	myconf_gn+=" proprietary_codecs=$(usex proprietary-codecs true false)"
	myconf_gn+=" ffmpeg_branding=\"${ffmpeg_branding}\""

	local myarch="$(tc-arch)"
	if [[ $myarch = amd64 ]] ; then
		myconf_gn+=" target_cpu=\"x64\""
		ffmpeg_target_arch=x64
	elif [[ $myarch = x86 ]] ; then
		myconf_gn+=" target_cpu=\"x86\""
		ffmpeg_target_arch=ia32
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
	myconf_gn+=" symbol_level=0"
	myconf_gn+=" use_gio=false"
	# myconf_gn+=" "

	# Avoid CFLAGS problems, bug #352457, bug #390147.
	# if ! use custom-cflags; then
		replace-flags "-Os" "-O2"
		strip-flags

		# Prevent linker from running out of address space, bug #471810 .
		if use x86; then
			filter-flags "-g*"
		fi

		# Prevent libvpx build failures. Bug 530248, 544702, 546984.
		if [[ ${myarch} == amd64 || ${myarch} == x86 ]]; then
			filter-flags -mno-mmx -mno-sse2 -mno-ssse3 -mno-sse4.1 -mno-avx -mno-avx2
		fi
	# fi

	if [[ ${CHROMIUM_FORCE_LIBCXX} == yes ]]; then
		append-flags -stdlib=libc++
		append-ldflags -stdlib=libc++
	fi

	# Bug 491582.
	export TMPDIR="${WORKDIR}/temp"
	mkdir -p -m 755 "${TMPDIR}" || die

	# https://bugs.gentoo.org/654216
	addpredict /dev/dri/ #nowarn

	# if ! use system-ffmpeg; then
		# local build_ffmpeg_args=""

		# if use pic && [[ "${ffmpeg_target_arch}" == "ia32" ]]; then
		# 	build_ffmpeg_args+=" --disable-asm"
		# fi

		# # Re-configure bundled ffmpeg. See bug #491378 for example reasons.
		# einfo "Configuring bundled ffmpeg..."

		# pushd third_party/ffmpeg > /dev/null || die
		# chromium/scripts/build_ffmpeg.py linux ${ffmpeg_target_arch} \
		# 	--branding ${ffmpeg_branding} -- ${build_ffmpeg_args} || die
		# chromium/scripts/copy_config.sh || die
		# chromium/scripts/generate_gn.py || die
		# popd > /dev/null || die
	# fi

	# bootstrap_gn

	einfo "Configuring Chromium..."
	set -- gn gen --args="${myconf_gn} ${EXTRA_GN}" out/Release
	echo "$@"
	"$@" || die
}

src_compile() {
	# Calling this here supports resumption via FEATURES=keepwork
	python_setup

	# https://bugs.gentoo.org/717456
	# ui/gfx/x/gen_xproto.py needs xcbgen
	local -x PYTHONPATH="${WORKDIR}:${WORKDIR}/setuptools-44.1.0:${PYTHONPATH+:}${PYTHONPATH}"

	#"${EPYTHON}" tools/clang/scripts/update.py --force-local-build --gcc-toolchain /usr --skip-checkout --use-system-cmake --without-android || die

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
