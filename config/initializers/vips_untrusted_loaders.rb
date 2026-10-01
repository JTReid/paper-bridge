# Temporary: Rails 8.1.4 makes this same call itself (CVE-2026-66066). Delete this
# file with the Rails upgrade, which waits on libvips 8.13+ in local development.
#
# Blocks libvips loaders that are unsafe for untrusted uploads, such as SVG. The
# formats PaperBridge accepts (JPEG, PNG, WebP, TIFF, HEIC, HEIF) stay available.
# libvips older than 8.13 cannot block loaders, so this is skipped there.
begin
  require "nokogiri" # Like Rails, load Nokogiri before libvips; both use libxml2.
  require "vips"
rescue LoadError
  # libvips is not installed in this environment, so there is nothing to block.
else
  Vips.block_untrusted(true) if Vips.respond_to?(:block_untrusted)
end
