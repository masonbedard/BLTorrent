class Peer
    attr_accessor :ip, :port, :socket, :connected, :am_choking, :am_interested, :is_choking, :is_interested, :tried, :pieces, :requests, :didRequest, :commSent, :commRecv
    def initialize(ip, port)
        @ip = ip
        @port = port
        @socket = nil
        @connected = false
        @am_choking = true
        @am_interested = false
        @is_choking = true
        @is_interested = false
        @tried = false
        @pieces = {}
        @requests = []
        @didRequest = false
        @isDownloading = false
        @commSent = nil
        @commRecv = nil
    end

    def to_s
      "Peer: <#{@ip}:#{@port} Connected: #{@connected}>"
    end
end