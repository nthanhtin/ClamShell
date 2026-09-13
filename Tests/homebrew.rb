require "digest"
require "open3"
require "rbconfig"
require "tmpdir"

updater = File.expand_path("../Tools/update-cask.rb", __dir__)
Dir.mktmpdir("clamshell-cask-") do |dir|
  archive = File.join(dir, "release.zip")
  cask = File.join(dir, "clamshell.rb")
  File.write(archive, "release contents")
  File.write(cask, "  version \"0.1.9\"\n  sha256 \"#{'0' * 64}\"\n  app \"ClamShell.app\"\n")
  run = ->(tag) { Open3.capture2e(RbConfig.ruby, updater, tag, archive, cask).last.success? }

  raise "Version update failed" unless run.call("v0.1.10")
  updated = File.read(cask)
  raise "Incorrect version" unless updated.include?('version "0.1.10"')
  raise "Incorrect checksum" unless updated.include?(Digest::SHA256.file(archive).hexdigest)
  raise "App stanza changed" unless updated.include?('app "ClamShell.app"')
  raise "Repeat update changed the cask" unless run.call("v0.1.10") && File.read(cask) == updated
  raise "Older release replaced the cask" unless run.call("v0.1.9") && File.read(cask) == updated
  raise "Invalid tag accepted" if run.call("v0.2.0-preview")
  raise "Invalid tag modified the cask" unless File.read(cask) == updated

  File.write(cask, "invalid cask")
  raise "Malformed cask accepted" if run.call("v0.2.0")
  raise "Malformed cask overwritten" unless File.read(cask) == "invalid cask"
end
puts "Homebrew update checks passed"
