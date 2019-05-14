# Copyright 1999-2019 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6
PYTHON_COMPAT=( python2_7 )
MY_PV="73.0.3683.103"
inherit check-reqs chromium-2 eutils unpacker flag-o-matic ninja-utils python-any-r1 toolchain-funcs versionator

RESTRICT="bindist mirror"
DESCRIPTION="Multi-threaded ffmpeg codecs needed for the HTML5 <audio> and <video> tags"
HOMEPAGE="http://www.chromium.org/Home"
LICENSE="BSD"
SLOT="0"
SRC_URI="
	https://commondatastorage.googleapis.com/chromium-browser-official/chromium-${MY_PV}.tar.xz -> ${P}.tar.xz
	http://gpo.ws54.tk/gentoo-distfiles/${P}.tar.xz
"
KEYWORDS="~amd64 ~x86"
IUSE="+component-build +proprietary-codecs pulseaudio x86? ( pic )"

COMMON_DEPEND="
	app-arch/bzip2:=
	dev-libs/expat:=
	dev-libs/glib:2
	>=dev-libs/libxml2-2.9.4-r3:=[icu]
	dev-libs/libxslt:=
	dev-libs/nspr:=
	>=dev-libs/re2-0.2016.05.01:=
	>=media-libs/alsa-lib-1.0.19:=
	media-libs/fontconfig:=
	media-libs/freetype:=
	>=media-libs/harfbuzz-2.0.0:0=[icu(-)]
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
	$(python_gen_any_dep '
		dev-python/beautifulsoup:python-2[${PYTHON_USEDEP}]
		>=dev-python/beautifulsoup-4.3.2:4[${PYTHON_USEDEP}]
		dev-python/html5lib[${PYTHON_USEDEP}]
		dev-python/simplejson[${PYTHON_USEDEP}]
	')
"
	# >=sys-devel/clang-5

: ${CHROMIUM_FORCE_CLANG=no}

if [[ ${CHROMIUM_FORCE_CLANG} == yes ]]; then
	DEPEND+=" >=sys-devel/clang-5"
fi

# Keep this in sync with the python_gen_any_dep call.
python_check_deps() {
	has_version --host-root "dev-python/beautifulsoup:python-2[${PYTHON_USEDEP}]" &&
	has_version --host-root ">=dev-python/beautifulsoup-4.3.2:4[${PYTHON_USEDEP}]" &&
	has_version --host-root "dev-python/html5lib[${PYTHON_USEDEP}]" &&
	has_version --host-root "dev-python/simplejson[${PYTHON_USEDEP}]"
}

if ! has chromium_pkg_die ${EBUILD_DEATH_HOOKS}; then
	EBUILD_DEATH_HOOKS+=" chromium_pkg_die";
fi

DISABLE_AUTOFORMATTING="yes"
PATCHES=(
	"${FILESDIR}/73-allocator-shim-Swap-ALIGN_LINKAGE-and-SHIM_ALWAYS_EX.patch"
	"${FILESDIR}/73-color_utils-Use-std-sqrt-instead-of-std-sqrtf.patch"
	"${FILESDIR}/73-quic_flags_impl-Fix-GCC-build-after-618558.patch"
)

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
	find -name '*.py' | xargs sed -e 's|env python|&2|g' -e 's|bin/python|&2|g' -i || die

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
	myconf_gn+=" use_gold=false use_sysroot=false linux_use_bundled_binutils=false use_custom_libcxx=false"

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
	myconf_gn+=" enable_hevc_demuxing=true"
	myconf_gn+=" use_gio=false"
	myconf_gn+=" symbol_level=0"
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

	# https://bugs.gentoo.org/588596
	#append-cxxflags $(test-flags-CXX -fno-delete-null-pointer-checks)

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
	set -- gn gen out/Release --args="${myconf_gn}" -v --script-executable=/usr/bin/python2
	echo "$@"
	"$@" || die
}

src_compile() {
	# Calling this here supports resumption via FEATURES=keepwork
	python_setup

	#"${EPYTHON}" tools/clang/scripts/update.py --force-local-build --gcc-toolchain /usr --skip-checkout --use-system-cmake --without-android || die

	# Even though ninja autodetects number of CPUs, we respect
	# user's options, for debugging with -j 1 or any other reason.
	eninja -C out/Release -v media/ffmpeg
	# clang-5.0: warning: optimization flag '-fno-delete-null-pointer-checks' is not supported [-Wignored-optimization-argument]
	# warning: unknown warning option '-Wno-maybe-uninitialized'; did you mean '-Wno-uninitialized'? [-Wunknown-warning-option]
}

src_install() {
	keepdir "${EPREFIX}/${YANDEX_HOME}"
	strip out/Release/libffmpeg.so
	insinto "${YANDEX_HOME}"
	doins out/Release/libffmpeg.so
}
