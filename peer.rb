class Peer
    attr_accessor :ip, :port, :socket, :connected, :am_choking, :am_interested, :is_choking, :is_interested, :tried, :pieces, :requests
    def initialize(ip, port)
        @ip = ip
        @port = port
        @socket = nil
        @connected = false
        @am_choking = false
        @am_interested = false
        @is_choking = false
        @is_interested = false
        @tried = false
        @pieces = {}
        @requests = []
    end

    def to_s
      "Peer: <#{@ip}:#{@port} Connected: #{@connected}>"
    end
end