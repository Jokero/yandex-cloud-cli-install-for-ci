#!/usr/bin/env bash

# The MIT License (MIT)
#
# Copyright (c) 2018 YANDEX LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

set -euo pipefail

VERBOSE=${VERBOSE:-}
if [[ ${VERBOSE} != "" ]]; then
    set -x
fi

SYSTEM=${YC_INSTALL_TEST_SYSTEM:-$(uname -s)} # $(uname -o) is not supported on macOS for example.
MACHINE=${YC_INSTALL_TEST_MACHINE:-$(uname -m)}

GOOS=""
GOARCH=""
YC_BIN="yc"
SHELL_NAME=$(basename "${SHELL}")

CONTACT_SUPPORT_MESSAGE="If you think that this should not be, contact support and attach this message.
System info: $(uname -a)"

case ${SYSTEM} in
    Linux | GNU/Linux)
        GOOS="linux"
        ;;
    Darwin)
        GOOS="darwin"
        ;;
    CYGWIN* | MINGW* | MSYS* | Windows_NT | WindowsNT )
        GOOS="windows"
        YC_BIN="yc.exe"
        ;;
     *)
        printf "'%s' system is not supported yet, or something is going wrong.\\n" "${SYSTEM}", "${CONTACT_SUPPORT_MESSAGE}"
        exit 1
          ;;
esac

case ${MACHINE} in
    x86_64 | amd64 | i686-64)
        GOARCH="amd64"
        ;;
    i386 | i686 )
        GOARCH="386"
        ;;
     *)
        printf "'%s' machines are not supported yet, or something is going wrong.\\n%s" "${MACHINE}" "${CONTACT_SUPPORT_MESSAGE}"
        exit 1
          ;;
esac

DEFAULT_RC_PATH="${HOME}/.bashrc"

if [ "${SHELL_NAME}" != "bash" ]; then
    DEFAULT_RC_PATH="${HOME}/.${SHELL_NAME}rc"
elif [ "${SYSTEM}" = "Darwin" ]; then
    DEFAULT_RC_PATH="${HOME}/.bash_profile"
fi

COMPLETION_AVAILABLE=
if [ "${SHELL_NAME}" = "bash" ]; then
    COMPLETION_AVAILABLE=yes
fi

DEFAULT_INSTALL_PATH="${HOME}/yandex-cloud"
YC_INSTALL_PATH="${DEFAULT_INSTALL_PATH}"
RC_PATH=
NO_RC=
AUTO_RC=

while getopts "hi:r:na" opt ; do
    case "$opt" in
        i)
            YC_INSTALL_PATH="${OPTARG}"
            ;;
        r)
            RC_PATH="${OPTARG}"
            ;;
        n)
            NO_RC=yes
            ;;
        a)
            AUTO_RC=yes
            ;;
        h)
            echo "Usage: install [options...]"
            echo "Options:"
            echo " -i [INSTALL_DIR]    Installs to specified dir."
            echo " -r [RC_FILE]        Automatically modify RC_FILE with PATH modification and shell completion."
            echo " -n                  Don't modify rc file and don't ask about it."
            echo " -a                  Automatically modify default rc file with PATH modification and shell completion."
            echo " -h                  Prints help."
            exit 0
            ;;
    esac
done

CURL_HELP="${YC_TEST_CURL_HELP:-$(curl --help)}"
CURL_OPTIONS=("-fS")
function curl_has_option {
    echo "${CURL_HELP}" | grep -e "$@" > /dev/null
}
if curl_has_option "--retry"; then
    # Added in curl 7.12.3
    CURL_OPTIONS=("${CURL_OPTIONS[@]}" "--retry" "5" "--retry-delay" "0" "--retry-max-time" "120")
fi
if curl_has_option "--connect-timeout"; then
    # Added in curl 7.32.0.
    CURL_OPTIONS=("${CURL_OPTIONS[@]}" "--connect-timeout" "5" "--max-time" "300")
fi
if curl_has_option "--retry-connrefused"; then
    # Added in curl 7.52.0.
    CURL_OPTIONS=("${CURL_OPTIONS[@]}" "--retry-connrefused")
fi
function curl_with_retry {
    curl "${CURL_OPTIONS[@]}" "$@"
}

YC_SDK_STORAGE_URL="${YC_SDK_STORAGE_URL:-"https://storage.yandexcloud.net/yandexcloud-yc"}"
YC_VERSION="${YC_VERSION:-$(curl_with_retry -s "${YC_SDK_STORAGE_URL}/release/stable")}"

if [ ! -t 0 ]; then
    # stdin is not terminal - we're piped. Skip all interactivity.
    AUTO_RC=yes
fi

echo "Downloading yc ${YC_VERSION}"

# Download to temp dir, check that executable is healthy, only then move to install path.
# That prevents partial download in case of download error or cancel.
TMPDIR="${TMPDIR:-/tmp}"
TMP_INSTALL_PATH=$(mktemp -d "${TMPDIR}/yc-install.XXXXXXXXX")
function cleanup {
    rm -rf "${TMP_INSTALL_PATH}"
}
trap cleanup EXIT

# Download and show progress.
TMP_YC="${TMP_INSTALL_PATH}/${YC_BIN}"
curl_with_retry "${YC_SDK_STORAGE_URL}/release/${YC_VERSION}/${GOOS}/${GOARCH}/${YC_BIN}" -o "${TMP_YC}"

chmod +x "${TMP_YC}"
# Check that all is ok, and print full version to stdout.
${TMP_YC} version || echo "Installation failed. Please contact support. System info: $(uname -a)"

mkdir -p "${YC_INSTALL_PATH}/bin"
YC="${YC_INSTALL_PATH}/bin/${YC_BIN}"
mv -f "${TMP_YC}" "${YC}"
mkdir -p "${YC_INSTALL_PATH}/.install"

case "${SHELL_NAME}" in
    bash | zsh)
        ;;
    *)
        echo "yc is installed to ${YC}"
        exit 0
        ;;
esac

YC_BASH_COMPLETION="${YC_INSTALL_PATH}/completion.bash.inc"
if [ "${COMPLETION_AVAILABLE}" = "yes" ]; then
    "${YC}" completion bash > "${YC_BASH_COMPLETION}"
fi
YC_BASH_PATH="${YC_INSTALL_PATH}/path.bash.inc"

if [ "${SHELL_NAME}" = "bash" ]; then
    cat >"${YC_BASH_PATH}" <<EOF
yc_dir="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
bin_path="\${yc_dir}/bin"
export PATH="\${bin_path}:\${PATH}"
EOF
else
    cat >"${YC_BASH_PATH}" <<EOF
yc_dir="\$(cd "\$(dirname "\${(%):-%N}")" && pwd)"
bin_path="\${yc_dir}/bin"
export PATH="\${bin_path}:\${PATH}"
EOF
fi

if [ "${NO_RC}" = "yes" ]; then
    exit 0
fi

function modify_rc() {
    if ! grep -Fq "if [ -f '${YC_BASH_PATH}' ]; then source '${YC_BASH_PATH}'; fi" "$1"; then
        cat >> "$1" <<EOF

# The next line updates PATH for Yandex Cloud CLI.
if [ -f '${YC_BASH_PATH}' ]; then source '${YC_BASH_PATH}'; fi
EOF
        echo ""
        echo "yc PATH has been added to your '${1}' profile"
    fi

    if ! grep -Fq "if [ -f '${YC_BASH_COMPLETION}' ]; then source '${YC_BASH_COMPLETION}'; fi" "$1"; then
        if [ "${COMPLETION_AVAILABLE}" = "yes" ]; then
            cat >> "$1" <<EOF

# The next line enables shell command completion for yc.
if [ -f '${YC_BASH_COMPLETION}' ]; then source '${YC_BASH_COMPLETION}'; fi
EOF
            echo "yc bash completion has been added to your '${1}' profile."
            if [ "${GOOS}" = "darwin" ]; then
                echo "Make sure bash-completion (brew install bash-completion) is installed and added to your .bash_profile"
            fi
        else
            echo "Shell command completion is not yet supported for ${SHELL_NAME}"
        fi
    fi

    "${YC}" components post-update

    echo "" >> "$1"
    echo "To complete installation, start a new shell (exec -l \$SHELL) or type 'source \"$1\"' in the current one"
}

if [ "${RC_PATH}" != "" ] ; then
    modify_rc "${RC_PATH}"
    exit 0
fi

if [ "${AUTO_RC}" = "yes" ]; then
    modify_rc "${DEFAULT_RC_PATH}"
    exit 0
fi
