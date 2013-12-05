class Peer
    attr_accessor :ip, :port, :socket, :connected, :am_chocking, :am_interested, :is_chocking, :is_interested, :tried, :pieces, :requests
    def initialize(ip, port)
        @ip = ip
        @port = port
        @socket = nil
        @connected = false
        @am_chocking = false
        @am_interested = false
        @is_chocking = false
        @is_interested = false
        @tried = false
        @pieces = {}
        @requests = []
    end

    def to_s
      "Peer: <#{@ip}:#{@port} Connected: #{@connected}>"
    end
end