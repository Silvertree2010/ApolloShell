class Apolloshell < Formula
  desc "Caelestia-inspired desktop shell for macOS: sidebar dock, launcher, dashboard"
  homepage "https://github.com/Silvertree2010/ApolloShell"
  url "https://github.com/Silvertree2010/ApolloShell/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "4cf968cd4fb59c0c2e6e802685cfa04405f0d551a457e96fd62085a01e42999d"
  license "MIT"
  head "https://github.com/Silvertree2010/ApolloShell.git", branch: "main"

  depends_on macos: :tahoe

  def install
    sdk = "/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
    ENV["SDKROOT"] = sdk if File.directory?(sdk)

    args = %w[--disable-sandbox -c release --product ApolloShell]
    system "swift", "build", *args
    bin_path = Utils.safe_popen_read("swift", "build", *args, "--show-bin-path").chomp

    ENV["BUILD_NUMBER"] = version.to_s
    ENV["HOMEBREW_BUILD"] = "1"
    system "scripts/assemble-app.sh", "#{bin_path}/ApolloShell", "#{buildpath}/ApolloShell.app"
    prefix.install "ApolloShell.app"
    pkgshare.install "scripts/setup-signing.sh"
  end

  def caveats
    <<~EOS
      ApolloShell.app is in:

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
        brew reinstall apolloshell
      (If the Homebrew build cannot reach your keychain, build with
      ./build.sh from a git checkout instead.)

      Updates: this copy belongs to Homebrew, so ApolloShell does not
      replace itself. It says when a new version is out; install it with
        brew upgrade apolloshell

      Start at login: System Settings > General > Login Items.
    EOS
  end

  test do
    app = prefix/"ApolloShell.app"
    assert_path_exists app/"Contents/MacOS/ApolloShell"
    assert_path_exists app/"Contents/Frameworks/MediaRemoteAdapter.framework"
    assert_path_exists app/"Contents/Frameworks/Sparkle.framework"
    assert_path_exists app/"Contents/Resources/installed-by-homebrew"
    system "codesign", "--verify", "--deep", "--strict", app
  end
end
