module OpenProject
  module Worklogs
    # Serves the plugin's CSS/JS straight from the gem instead of through
    # sprockets.
    #
    # The slim image ships a precompiled asset manifest and skips
    # `assets:precompile` entirely, so anything we added to the sprockets load
    # path would simply never be built. These two files are plain, dependency-free
    # ES2020/CSS, fingerprinted here and served with an immutable cache header.
    module Assets
      CONTENT_TYPES = {
        ".css" => "text/css",
        ".js" => "text/javascript"
      }.freeze

      class << self
        def path(filename)
          "/worklogs/assets/#{digest(filename)}/#{filename}"
        end

        def file_path(filename)
          return nil unless permitted?(filename)

          full = root.join(filename)
          full.file? ? full : nil
        end

        def content_type(filename)
          CONTENT_TYPES.fetch(File.extname(filename), "application/octet-stream")
        end

        def digest(filename)
          digests[filename] ||= begin
            file = file_path(filename)
            file ? Digest::SHA256.file(file).hexdigest[0, 12] : "missing"
          end
        end

        private

        def digests
          @digests ||= {}
        end

        def root
          Engine.root.join("public")
        end

        # Guard against traversal: only flat names of the asset types we ship.
        def permitted?(filename)
          filename.to_s.match?(/\A[\w-]+\.(css|js)\z/)
        end
      end
    end
  end
end
