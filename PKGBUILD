# Maintainer: your name <you@example.com>
# PKGBUILD for docker-iptables-guard

pkgname=docker-iptables-guard
pkgver=0.1.4
pkgrel=1
pkgdesc="Reassert hotspot iptables invariants after Docker networking events"
arch=('x86_64')
license=('MIT')
url="https://example.com/"
depends=('bash' 'iptables' 'iw' 'iproute2' 'docker')

source=(
  'docker-iptables-guard.sh'
  'ensure-hotspot-iptables.sh'
  'docker-iptables-guard.service'
)
sha256sums=('SKIP' 'SKIP' 'SKIP')

build() {
  : # no build step
}

package() {
  # install scripts to /usr/bin
  install -Dm755 "${srcdir}/docker-iptables-guard.sh" "${pkgdir}/usr/bin/docker-iptables-guard.sh"
  install -Dm755 "${srcdir}/ensure-hotspot-iptables.sh" "${pkgdir}/usr/bin/ensure-hotspot-iptables.sh"

  # rewrite ExecStart in systemd unit to point at /usr/bin/docker-iptables-guard.sh (preserve extra args)
  sed -E 's#^ExecStart=[^ ]+#ExecStart=/usr/bin/docker-iptables-guard.sh#' "${srcdir}/docker-iptables-guard.service" > "${srcdir}/docker-iptables-guard.service.installed"

  install -Dm644 "${srcdir}/docker-iptables-guard.service.installed" "${pkgdir}/usr/lib/systemd/system/docker-iptables-guard.service"
}
