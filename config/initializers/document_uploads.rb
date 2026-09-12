# Allow document batches without a separate Rack limit on multipart counts.
Rack::Utils.multipart_file_limit = 0
Rack::Utils.multipart_total_part_limit = 0
