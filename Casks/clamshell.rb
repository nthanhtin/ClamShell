cask "clamshell" do
  version "0.1.0"
  sha256 "bf8cfae6b4f0c5b01025c892259f952ed9d641766eae78f1c20d0333e4fd6fcb"

  url "https://github.com/nthanhtin/ClamShell/releases/download/v#{version}/ClamShell-v#{version}-arm64.zip"
  name "ClamShell"
  desc "Desktop fold animation that follows the lid angle"
  homepage "https://github.com/nthanhtin/ClamShell"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "ClamShell.app"

  caveats <<~EOS
    This hobby build is ad hoc signed and isn't notarized.
    If macOS blocks it, follow Apple's Open Anyway instructions:
      https://support.apple.com/en-us/102445
  EOS
end
