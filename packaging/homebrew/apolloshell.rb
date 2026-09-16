# Homebrew formula template for ApolloShell - builds from source.
#
# Publish it in a tap repository named "homebrew-apolloshell" (so users can
# run `brew tap OWNER/apolloshell`). Before publishing, replace OWNER and set
# sha256 to `shasum -a 256` of the release tarball.
#
# Only the Command Line Tools are needed (swift, clang, codesign, iconutil
# are not even required - the icon is prebuilt). Xcode is NOT required.
class Apolloshell < Formula
  desc "Caelestia-inspired desktop shell for macOS: sidebar dock, launcher, dashboard"
  homepage "https://github.com/OWNER/ApolloShell"
  url "https://github.com/OWNER/ApolloShell/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/OWNER/ApolloShell.git", branch: "main"

  # Liquid Glass (NSGlassEffectView) exists from macOS 26 Tahoe on.
  depends_on macos: :tahoe

  def install
    # Newer Command Line Tools default to an SDK that does not match their
    # compiler; pin the macOS 26 SDK when it is there (same as build.sh).
    sdk = "/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
    ENV["SDKROOT"] = sdk if File.directory?(sdk)

    args = %w[--disable-sandbox -c release --product ApolloShell]
    system "swift", "build", *args
    bin_path = Utils.safe_popen_read("swift", "build", *args, "--show-bin-path").chomp

    # Signs with the local identity from scripts/setup-signing.sh if the
    # keychain offers it, otherwise ad-hoc (see caveats).
    ENV["BUILD_NUMBER"] = version.to_s
    system "scripts/assemble-app.sh", "#{bin_path}/ApolloShell", "#{buildpath}/ApolloShell.app"
    prefix.install "ApolloShell.app"
    pkgshare.install "scripts/setup-signing.sh"
  end

  def caveats
    <<~EOS
      ApolloShell.app is in:
        #{opt_prefix}/ApolloShell.app

      To find it in Spotlight and Launchpad, link it into ~/Applications:
        mkdir -p ~/Applications
        ln -sf "#{opt_prefix}/ApolloShell.app" ~/Applications/ApolloShell.app

      Permissions (System Settings > Privacy & Security):
        Accessibility  - window guard, dock window list and badges, Spaces
                         and keyboard actions. macOS asks on first launch.
        Automation     - "System Events", for log out / restart / shut down.

      The app is signed ad-hoc unless you created a local signing identity.
      Ad-hoc signatures change with every build, so the Accessibility grant
      has to be given again after each upgrade. For a stable signature:
        #{opt_pkgshare}/setup-signing.sh
        brew reinstall apolloshell
      (If the Homebrew build cannot reach your keychain, build with
      ./build.sh from a git checkout instead.)

      Start at login: System Settings > General > Login Items.
    EOS
  end

  test do
    app = prefix/"ApolloShell.app"
    assert_path_exists app/"Contents/MacOS/ApolloShell"
    assert_path_exists app/"Contents/Frameworks/MediaRemoteAdapter.framework"
    system "codesign", "--verify", "--deep", "--strict", app
  end
end
