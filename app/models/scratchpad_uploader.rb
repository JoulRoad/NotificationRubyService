class FilelessIO < StringIO
    attr_accessor :original_filename, :content_type
  end
  
  class ScratchpadUploader < CarrierWave::Uploader::Base
    include CarrierWave::MimeTypes
    process :set_content_type
  
    # Include image processing support (RMagick or MiniMagick)
    include CarrierWave::RMagick
    # Alternatively, if you prefer MiniMagick:
    # include CarrierWave::MiniMagick
  
    # Use Fog for cloud storage.
    storage :fog
  
    # Override the directory where uploaded files will be stored.
    def store_dir
      "scraps/"
    end
  
    # Sanitizes the given string by replacing spaces with underscores.
    def sanitize(cat)
      cat.gsub(" ", "_")
    end
  
    # Uploads a scratchpad image from a Base64-encoded string.
    def upload_scratchpad(filename, base64)
      @store_location = "scraps/"
      decoded_data = Base64.decode64(base64.gsub("data:image/png;base64,", ""))
      io = FilelessIO.new(decoded_data)
      io.original_filename = filename
      io.content_type = "image/png"
      store!(io)
      url
    end
  end
  