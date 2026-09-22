# NOT VITRINE'S CASK. This formula installs `Prizm` from b0x42's releases — the upstream project this
# repository was forked from before it was renamed. It is kept because `b0x42/homebrew-prizm` is the
# only tap that exists, and deleting the file would not make a Vitrine tap appear.
#
# Vitrine has no cask: that needs a tap repository of its own plus a published release here. Until
# then README's install section says so plainly rather than pointing here.
cask "prizm" do
  version "1.4.3"
  sha256 :no_check

  url "https://github.com/b0x42/prizm/releases/download/v#{version}/Prizm-v#{version}.dmg"
  name "Prizm"
  desc "Native macOS client for Vaultwarden and self-hosted Bitwarden"
  homepage "https://github.com/b0x42/prizm"

  depends_on macos: ">= :tahoe"

  app "Prizm.app"
end
