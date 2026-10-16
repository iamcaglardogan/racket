# UNRELEASED TEMPLATE. Do not install or publish this cask until a notarized
# GitHub release is public and both version and sha256 are replaced and verified.
cask "racket" do
  version "REPLACE_WITH_RELEASE_VERSION"
  sha256 "REPLACE_WITH_NOTARIZED_ZIP_SHA256"

  url "https://github.com/iamcaglardogan/racket/releases/download/v#{version}/RACKET-#{version}-macOS.zip"
  name "RACKET"
  desc "Private, review-first storage cleanup for creative professionals"
  homepage "https://github.com/iamcaglardogan/racket"

  depends_on macos: ">= :sonoma"

  app "RACKET.app"

  # A future public cask must deliberately preserve recovery journals and user
  # exclusions. No zap directive is supplied in this unreleased template.
end
