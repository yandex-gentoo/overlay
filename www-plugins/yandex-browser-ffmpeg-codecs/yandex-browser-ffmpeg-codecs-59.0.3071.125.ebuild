# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6
PYTHON_COMPAT=( python2_7 )

inherit check-reqs chromium-2 eutils unpacker flag-o-matic ninja-utils python-any-r1

RESTRICT="bindist mirror"
DESCRIPTION="Multi-threaded ffmpeg codecs needed for the HTML5 <audio> and <video> tags"
HOMEPAGE="http://www.chromium.org/Home"
LICENSE="BSD"
SLOT="0"
SRC_URI="https://commondatastorage.googleapis.com/chromium-browser-official/chromium-${PV}.tar.xz"
KEYWORDS="~x86 ~amd64"
IUSE="+component-build +proprietary-codecs pulseaudio"

COMMON_DEPEND="
	app-arch/bzip2:=
	dev-libs/expat:=
	dev-libs/glib:2
	<dev-libs/icu-59:=
	dev-libs/libxslt:=
	dev-libs/nspr:=
	>=dev-libs/nss-3.14.3:=
	>=dev-libs/re2-0.2016.05.01:=
	>=media-libs/alsa-lib-1.0.19:=
	media-libs/fontconfig:=
	media-libs/freetype:=
	>=media-libs/harfbuzz-1.4.2:=[icu(-)]
	media-libs/libjpeg-turbo:=
	media-libs/libpng:=
	>=media-libs/openh264-1.6.0:=
	pulseaudio? ( media-sound/pulseaudio:= )
	sys-apps/dbus:=
	sys-apps/pciutils:=
	virtual/udev
	x11-libs/cairo:=
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3[X]
	x11-libs/libX11:=
	x11-libs/libXcomposite:=
	x11-libs/libXcursor:=
	x11-libs/libXdamage:=
	x11-libs/libXext:=
	x11-libs/libXfixes:=
	>=x11-libs/libXi-1.6.0:=
	x11-libs/libXrandr:=
	x11-libs/libXrender:=
	x11-libs/libXScrnSaver:=
	x11-libs/libXtst:=
	x11-libs/pango:=
	app-arch/snappy:=
	media-libs/flac:=
	>=media-libs/libwebp-0.4.0:=
	sys-libs/zlib:=[minizip]
"

RDEPEND="
	sys-libs/glibc
"
DEPEND="${COMMON_DEPEND}
	>=app-arch/gzip-1.7
	dev-lang/yasm
	dev-lang/perl
	>=dev-util/gperf-3.0.3
	dev-util/ninja
	>=net-libs/nodejs-4.6.1
	sys-apps/hwids[usb(+)]
	>=sys-devel/bison-2.4.3
	sys-devel/flex
	virtual/pkgconfig
	dev-vcs/git
	$(python_gen_any_dep '
		dev-python/beautifulsoup:python-2[${PYTHON_USEDEP}]
		>=dev-python/beautifulsoup-4.3.2:4[${PYTHON_USEDEP}]
		dev-python/html5lib[${PYTHON_USEDEP}]
		dev-python/simplejson[${PYTHON_USEDEP}]
	')
"

# Keep this in sync with the python_gen_any_dep call.
python_check_deps() {
	has_version --host-root "dev-python/beautifulsoup:python-2[${PYTHON_USEDEP}]" &&
	has_version --host-root ">=dev-python/beautifulsoup-4.3.2:4[${PYTHON_USEDEP}]" &&
	has_version --host-root "dev-python/html5lib[${PYTHON_USEDEP}]" &&
	has_version --host-root "dev-python/simplejson[${PYTHON_USEDEP}]"
}

DISABLE_AUTOFORMATTING="yes"

S="${WORKDIR}/chromium-${PV}"
YANDEX_HOME="opt/yandex/browser-beta"

pre_build_checks() {
	if [[ ${MERGE_TYPE} != binary ]]; then
		local -x CPP="$(tc-getCXX) -E"
		if tc-is-clang && ! version_is_at_least "3.9.1" "$(clang-fullversion)"; then
			# bugs: #601654
			die "At least clang 3.9.1 is required"
		fi
		if tc-is-gcc && ! version_is_at_least 5.0 "$(gcc-version)"; then
			# bugs: #535730, #525374, #518668, #600288, #627356
			die "At least gcc 5.0 is required"
		fi
	fi

	# Check build requirements, bug #541816 and bug #471810 .
	CHECKREQS_MEMORY="3G"
	CHECKREQS_DISK_BUILD="5G"
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

src_prepare() {
	# Use Python 2
	find . -name '*.py' -exec sed -r 's|/usr/bin/python$|&2|g' -i {} +
	find . -name '*.py' -exec sed -r 's|/usr/bin/env python$|&2|g' -i {} +

	# There are still a lot of relative calls which need a workaround
	[[ -d "${WORKDIR}/python2-path" ]] && rm -rf "${WORKDIR}/python2-path"
	mkdir "${WORKDIR}/python2-path"
	ln -s /usr/bin/python2 "${WORKDIR}/python2-path/python"

	local PATCHES=(
		"${FILESDIR}/chromium-FORTIFY_SOURCE.patch"
		"${FILESDIR}/chromium-dma-buf-r1.patch"
	)

	default

	mkdir -p third_party/node/linux/node-linux-x64/bin || die
	ln -s "${EPREFIX}"/usr/bin/node third_party/node/linux/node-linux-x64/bin/node || die
}

src_configure() {
	local myarch="$(tc-arch)"
	local myconf_gn=""

	myconf_gn+=" is_debug=false"
	myconf_gn+=" is_component_build=true"
	myconf_gn+=" use_allocator=\"none\""
	myconf_gn+=" use_cups=false"
	myconf_gn+=" use_gconf=false"
	myconf_gn+=" use_gnome_keyring=false"
	myconf_gn+=" use_gtk3=true"
	myconf_gn+=" use_kerberos=false"
	myconf_gn+=" use_pulseaudio=$(usex pulseaudio true false)"
	# TODO: link_pulseaudio=true for GN.
	myconf_gn+=" is_clang=false"
	myconf_gn+=" use_gold=false use_sysroot=false linux_use_bundled_binutils=false"

	ffmpeg_branding="ChromeOS"

	myconf_gn+=" proprietary_codecs=true"
	myconf_gn+=" ffmpeg_branding=\"${ffmpeg_branding}\""

	if [[ $myarch = amd64 ]] ; then
		myconf_gn+=" target_cpu=\"x64\""
		ffmpeg_target_arch=x64
	elif [[ $myarch = x86 ]] ; then
		myconf_gn+=" target_cpu=\"x86\""
		ffmpeg_target_arch=ia32
	else
		die "Failed to determine target arch, got '$myarch'."
	fi

	myconf_gn+=" treat_warnings_as_errors=false"
	myconf_gn+=" fatal_linker_warnings=false"
	# Additional conf
	# myconf_gn+=" enable_hevc_demuxing=true"
	myconf_gn+=" use_gio=false"
	myconf_gn+=" symbol_level=0"
	# myconf_gn+=" "

	replace-flags "-Os" "-O2"
	strip-flags

	# Prevent linker from running out of address space, bug #471810 .
	if use x86; then
		filter-flags "-g*"
	fi

	# # Prevent libvpx build failures. Bug 530248, 544702, 546984.
	# if [[ ${myarch} == amd64 || ${myarch} == x86 ]]; then
	# 	filter-flags -mno-mmx -mno-sse2 -mno-ssse3 -mno-sse4.1 -mno-avx -mno-avx2
	# fi

	tc-export AR CC CXX NM

	# myconf_gn+=" custom_toolchain=\"${FILESDIR}/toolchain:default\""
	append-cxxflags $(test-flags-CXX -fno-delete-null-pointer-checks)

	export TMPDIR="${WORKDIR}/temp"
	mkdir -p -m 755 "${TMPDIR}" || die

	local build_ffmpeg_args=""
	# if use pic && [[ "${ffmpeg_target_arch}" == "ia32" ]]; then
	# 	build_ffmpeg_args+=" --disable-asm"
	# fi

	# Re-configure bundled ffmpeg. See bug #491378 for example reasons.
	einfo "Configuring bundled ffmpeg..."

	pushd third_party/ffmpeg > /dev/null || die
	chromium/scripts/build_ffmpeg.py linux ${ffmpeg_target_arch} \
		--branding ${ffmpeg_branding} -- ${build_ffmpeg_args} || die
	chromium/scripts/copy_config.sh || die
	chromium/scripts/generate_gn.py || die
	popd > /dev/null || die

	touch chrome/test/data/webui/i18n_process_css_test.html || die

	einfo "Building GN..."
	set -- tools/gn/bootstrap/bootstrap.py -s -v --no-clean --gn-gen-args "${myconf_gn}"
	echo "$@"
	"$@" || die

	einfo "Configuring Chromium..."
	set -- out/Release/gn gen out/Release --args="${myconf_gn}" -v --script-executable=/usr/bin/python2
	echo "$@"
	"$@" || die

}

src_compile() {
	eninja -C out/Release -v media/ffmpeg
}

src_install() {
	keepdir "${YANDEX_HOME}"
	strip out/Release/libffmpeg.so
	insinto "${YANDEX_HOME}"
	doins out/Release/libffmpeg.so
}
