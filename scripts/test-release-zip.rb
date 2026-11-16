#!/usr/bin/env ruby
require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'digest'
require 'open3'

class ReleaseZipTests < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('status-trio-zip-test-')
    @name = 'StatusTrio-1.0.0.zip'
    @data = 'ZIP fixture of a stapled app'
    File.binwrite(File.join(@dir, @name), @data)
    @entry = {'filename'=>@name, 'length'=>@data.bytesize.to_s, 'sha256'=>Digest::SHA256.hexdigest(@data), 'ed_signature'=>'zip-signature'}
    @manifest = {'schema_version'=>1,'version'=>'1.0.0','tag'=>'v1.0.0','source_sha'=>'a'*40,'zip'=>@entry}
    File.write(File.join(@dir, @name+'.sha256'), @entry['sha256']+'  '+@name+"\n")
  end
  def teardown
    FileUtils.remove_entry(@dir)
  end
  def verify
    path = File.join(@dir,'release-manifest.json')
    File.write(path, JSON.generate(@manifest))
    Open3.capture3('ruby', File.expand_path('verify-release-zip.rb', __dir__), path, @dir)
  end
  def test_accepts_exact_original_archive
    out, err, status = verify
    assert status.success?, err
    assert_equal @name, out.strip
  end
  def test_legacy_manifest_without_zip_remains_recoverable
    @manifest.delete('zip')
    out, err, status = verify
    assert status.success?, err
    assert_empty out
  end
  def test_refuses_tampered_bytes_missing_sidecar_and_unsafe_identity
    [-> { File.binwrite(File.join(@dir,@name), 'other') },
     -> { File.unlink(File.join(@dir,@name+'.sha256')) },
     -> { @entry['filename']='../elsewhere.zip' },
     -> { @entry['ed_signature']='diagnostic-not-for-publication' },
     -> { @entry['length']='1' },
     -> { @entry['sha256']='0'*64 }].each do |mutate|
      teardown
      setup
      begin
        mutate.call
        _out, _err, status = verify
        refute status.success?
      ensure
        # The next iteration recreates its isolated package.
      end
    end
  end
end
