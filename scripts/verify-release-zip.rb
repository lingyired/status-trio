#!/usr/bin/env ruby
# Optional schema-v1 ZIP extension. Historical DMG-only artifacts stay valid.
require 'json'
require 'digest'
manifest_path, directory = ARGV
abort('usage: verify-release-zip.rb <manifest> <package-directory>') unless manifest_path && directory
manifest = JSON.parse(File.read(manifest_path))
exit 0 unless manifest.key?('zip')
zip = manifest.fetch('zip')
abort('ZIP manifest must be an object') unless zip.is_a?(Hash)
filename = zip.fetch('filename')
expected = "StatusTrio-#{manifest.fetch('version')}.zip"
abort('ZIP filename identity mismatch') unless filename == expected && filename.match?(/\AStatusTrio-[0-9]+(?:\.[0-9]+)*\.zip\z/)
length = zip.fetch('length').to_s
abort('ZIP length invalid') unless length.match?(/\A[1-9][0-9]*\z/)
sha = zip.fetch('sha256')
abort('ZIP digest invalid') unless sha.is_a?(String) && sha.match?(/\A[a-f0-9]{64}\z/)
signature = zip.fetch('ed_signature')
abort('ZIP must have its own publishable EdDSA signature') unless signature.is_a?(String) && !signature.empty? && signature != 'diagnostic-not-for-publication'
path = File.join(directory, filename)
abort('ZIP archive or checksum missing') unless File.file?(path) && File.file?(path+'.sha256')
abort('ZIP length mismatch') unless File.size(path) == Integer(length, 10)
abort('ZIP SHA-256 mismatch') unless Digest::SHA256.file(path).hexdigest == sha
abort('ZIP checksum sidecar mismatch') unless File.read(path+'.sha256').strip == "#{sha}  #{filename}"
puts filename
