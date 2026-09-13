require "digest"
require "rubygems"

abort "Usage: ruby Tools/update-cask.rb vX.Y.Z archive.zip cask.rb" unless ARGV.length == 3
tag, archive, path = ARGV
abort "Expected a version tag such as v0.1.1" unless tag.match?(/\Av\d+\.\d+\.\d+\z/)

source = File.read(path)
version = tag.delete_prefix("v")
version_line = /^  version "(\d+\.\d+\.\d+)"$/
checksum_line = /^  sha256 "[a-f0-9]{64}"$/
abort "Expected one version and checksum in the cask" unless
  source.scan(version_line).length == 1 && source.scan(checksum_line).length == 1

# Releases can finish out of order; keep the newest version in the tap.
if Gem::Version.new(version) < Gem::Version.new(source[version_line, 1])
  puts "Keeping the newer Homebrew version"
  exit
end

checksum = Digest::SHA256.file(archive).hexdigest
source.sub!(version_line, "  version \"#{version}\"")
source.sub!(checksum_line, "  sha256 \"#{checksum}\"")
File.write(path, source)
