module Shelly
  class Backup < Model
    LIMIT = 10
    attr_reader :filename, :size, :human_size, :code_name, :kind, :state

    def initialize(attributes = {})
      @filename   = attributes["filename"]
      @size       = attributes["size"]
      @human_size = attributes["human_size"]
      @code_name  = attributes["code_name"]
      @kind       = attributes["kind"]
      @state      = attributes["state"]
    end

    def download(callback)
      url = shelly.download_backup_url(code_name, filename)
      shelly.download_file(code_name, filename, url, callback)
    end
  end
end
