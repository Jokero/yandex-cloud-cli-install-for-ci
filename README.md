# Yandex Cloud CLI installation script for CI environments

## Motivation

The existing installation script available on https://storage.yandexcloud.net/yandexcloud-yc/install.sh 
is not suitable for using in non-interactive environments (for example in CI) as it's asking a user for text input.

This repo provides a modified script that does not have such problem and allows to install Yandex Cloud CLI in
continuous integration environment.

## Usage

To install the latest stable version of Yandex Cloud CLI:

```sh
curl https://raw.githubusercontent.com/Jokero/yandex-cloud-cli-install-for-ci/master/install.sh | bash
source ~/.bashrc
```

To install a specific version:
```sh
curl https://raw.githubusercontent.com/Jokero/yandex-cloud-cli-install-for-ci/master/install.sh > install.sh
chmod 700 install.sh && YC_VERSION=0.35.0 ./install.sh
source ~/.bashrc
```