require './event'
require './client'
require 'timeout'

def getHex(number, padding)
  return [number.to_s(16).rjust(padding, '0')].pack("H*")
end

class Peer
  include Event

  event :noActivity

  attr_accessor :ip, :port, :socket, :connected, :am_choking, :am_interested, 
                :is_choking, :is_interested, :connecting, :requestsToTimes, 
                :commSent, :commRecv, :requestsFrom, :blacklisted, :havePieces,
                :is_seeder, :bytesFromThisSecond,
                :rollingAverage, :timeOfLastAverage
  def initialize(client, ip, port)
    @client = client
    @ip = ip
    @port = port
    @socket = nil
    @connected = false
    @am_choking = true
    @am_interested = false
    @is_choking = true
    @is_interested = false
    @connecting = false
    @requestsFrom = []
    @requestsToTimes = []
    @commSent = nil
    @commRecv = nil
    @listenThread = nil
    @blacklisted = false
    @havePieces = []
    @is_seeder = false

    #just added these
    @bytesFromThisSecond = 0
    @timeOfLastAverage = Time.now
    @rollingAverage = []

    @timeOfLastBlockFrom

  end

  def to_s
    "Peer: <#{@ip}:#{@port} Connected: #{@connected}>"
  end

  def sendHandshake(infoHash, peerId)
    @connecting = true
    Thread.new {
      data = "\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{infoHash}#{peerId}"
      
      begin 
        Timeout::timeout(10) {
          @socket = TCPSocket.new(@ip, @port)
          @socket.write data
          handshake = @socket.read 68 # TODO add check for info hash
        }
        @commSent = Time.now
        @commRecv = Time.now 
        @connected = true
        @connecting = false
        @client.send_event(:peerConnect, self)

        @listenThread = Thread.new { 
#          p "Listen thread started for #{self}"
          while @connected do 
            listenForMessages 
          end 
        }
        on_event(self, :noActivity) {
#          p "eventh"
          @listenThread.terminate
          disconnect("No connectivity seen")
        }
      rescue Errno::ECONNRESET, Timeout::Error, Errno::ECONNREFUSED, Errno::ENETUNREACH
        @blacklisted = true
        @connecting = false
        @client.send_event(:peerTimeout, self)
      end 
    }
  end

  def disconnect(reason)
    begin
      @client.send_event(:peerDisconnect, self, reason)
      @listenThread.terminate
      @blacklisted = true
      @connected = false
      clearRequests
      @socket.close
    rescue Exception => e
#      p "Exception in disconnect #{e}"
    end
  end

  def listenForMessages
    data = ""
    while data.length < 4 do
      begin 
        data = @socket.recv(4 - data.length) # block until we get 4 bytes
      rescue Errno::ECONNRESET, IOError
        disconnect("Peer reset connection")
        return
      end
      if data.nil? or data.empty? then # then called fin on us, those bitches
        disconnect("Peer closed connection")
        return
      end
    end

    @commRecv = Time.now # got a message from peer
    len = data.unpack("H*")[0].to_i(16)
    if len > 0 then
      message = ""
      begin
        while message.length < len
          Timeout::timeout(10) {
            data = @socket.recv(len - message.length)
            if data.nil? or data.empty? then
              disconnect("Peer closed connection")
              return
            end
            message.concat data
          }
        end 
#        p "Length: #{len} got: #{message.length}"
        parseMessage(message)
      rescue Timeout::Error
        disconnect("Timeout while getting data")
        return
      rescue Errno::ECONNRESET
        disconnect("Peer reset connection")
        return
      rescue Errno::EBADF
        disconnect("Bad file descriptor")
        return
      end
    else 
#      p "Got keep alive from #{self}"
    end
  end

  def sendMessage(type, first=nil, second=nil, third=nil)
#    p "sending message of type #{type}"
    data = createMessage(type, first, second, third)
    begin
      case type
      when :keepalive
        socket.write data
      when :choke
        @am_choking = true
        socket.write data
      when :unchoke
        @am_choking = false
        socket.write data
      when :interested
        @am_interested = true
#        p 'sending out shit here'
        socket.write data
      when :uninterested
        @am_interested = false
        socket.write data
      when :have, :bitfield, :piece, :piece, :cancel, :port
        socket.write data
      when :request
        @requestsToTimes.push([Time.now, first, second])
        #p "sent a request ################################################ piece: #{first} offset #{second}  len #{third}"
        #p "to #{self}"
        #puts data.unpack("H*")
        socket.write data
      when :cancel
        p 'CANCELING CAUSE OF END GAME THATS THE ONLY REASON WE CANCEL AT THE MOMENT WHY ELSE WOULD YOU'
        socket.write data
      else
        raise "No message of type #{type}"
      end
      @commSent = Time.now
    rescue Errno::EPIPE, IOError => e
      disconnect("Peer threw exception #{e}")
    end
  end

  def createMessage(type, first=nil, second=nil, third=nil)
    case type
    when :keepalive
      data = "\x00\x00\x00\x00"
    when :choke
      data = "\x00\x00\x00\x01\x00"
    when :unchoke
      data = "\x00\x00\x00\x01\x01"
    when :interested
      data = "\x00\x00\x00\x01\x02"
    when :notinterested
      data = "\x00\x00\x00\x01\x03"
    when :have
      data = "\x00\x00\x00\x05\x04"
      data += getHex(first, 8)
    when :bitfield
      bitfield = ""
      @client.pieces.each { |p|
        if p.verified then
          bitfield += "1"
        else
          bitfield += "0"
        end
      }

      i = bitfield.size
      while (i % 8) != 0
        bitfield += "0"
        i += 1
      end
      p bitfield
      bitfieldValue = bitfield.to_i(2)
      len = 1 + (bitfieldValue.to_s(16).size / 2)
      data = getHex(len, 8)
      data += "\x05"
      data += getHex(bitfieldValue, 0)
    when :request
      data = "\x00\x00\x00\x0d\x06"
      data += getHex(first, 8)
      data += getHex(second, 8)
      data += getHex(third, 8)
    when :piece
      len = 9 + third.size
      data = getHex(len, 8)
      data += "\x07"
      data += getHex(first, 8)
      data += getHex(second, 8)
      data += getHex(third, 0)
    when :cancel
      data = "\x00\x00\x00\x0d\x08"
      data += getHex(first, 8)
      data += getHex(second, 8)
      data += getHex(third, 8)
    when :port
      data = "\x00\x00\x00\x03\x09"
      data += getHex(first, 8)
    else
      raise "No message of type #{type}"
    end
    data
  end

  def isSeeder?
    if @havePieces.size == @client.metainfo.pieces.size
      @is_seeder = true
    end
  end

  def clearRequests
    for request in @requestsToTimes
      @client.pieces[request[1]].requested[request[2]] = nil 
    end
    @requestsToTimes = [] # probably not necessary? or wrong?
#    p 'cleared requests'
  end

  def parseMessage(message)
    case message[0]
    when "\x00"
#      p "choke from #{self}"
      @is_choking = true
      clearRequests
    when "\x01"
#      p "unchoke from #{self}"
      @is_choking = false
    when "\x02"
#      p "interested from #{self}"
      @is_interested = true

      if !@am_choking then
        @client.chokeAlgorithm
      end

    when "\x03"
#      p "uninterested from #{self}"
      @is_interested = false

      if !@am_choking then
        @client.chokeAlgorithm
      end

    when "\x04"
      pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
#      p "have from #{self} for piece #{pieceIndex}"
      if @client.rarity[pieceIndex] == nil then
        @client.rarity[pieceIndex] = []
      end
      peerIndex = @client.peers.index(self)
      if !@client.rarity[pieceIndex].include?(peerIndex) then
        @client.rarity[pieceIndex].push(peerIndex)
      end
      if !@havePieces.include?(pieceIndex) then
        @havePieces.push(pieceIndex)
      end
      isSeeder?
    when "\x05"
#      p "bitmap from #{self}"
      i = 1
      bitmap = ""
      messageLen = message.length
      while (i < messageLen)
        bitmap += message[i].unpack("H*")[0].to_i(16).to_s(2)
        i += 1
      end
      bitmapLen = bitmap.length
      i = 0
      while (i < bitmapLen)
        if bitmap[i] == "1"
          if @client.rarity[i] == nil
            @client.rarity[i] = []
          else
            peerIndex = @client.peers.index(self)
            if !@client.rarity[i].include?(peerIndex) then
              @client.rarity[i].push(peerIndex)
            end
          end
          if !@havePieces.include?(i) then
            @havePieces.push(i)
          end
        end
        i += 1
      end
      isSeeder?
      sendMessage(:interested)
    when "\x06"
      p 7509283745098273504987230985709234857098234750923750982374508723098457203498750923750923475
      p "request from #{self}"
      # TODO
      # pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
      # offset = message[5..8].unpack("H*")[0].to_i(16)
      # length = message[9..12].unpack("H*")[0].to_i(16)
      # @peers[peerIndex].requests.unshift(Request.new(pieceIndex, offset, length))
    when "\x07"
      pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
      offset = message[5..8].unpack("H*")[0].to_i(16)
      data = message[9..message.length]

      @bytesFromThisSecond += message.length    # ADDED THIS

      @timeOfLastBlockFrom = Time.now

      for request in @requestsToTimes
        if request[1] == pieceIndex && request[2] == offset then
          @requestsToTimes.delete(request)
          break
        end
      end
      @client.bytesInInterval += data.length
      if @client.endGameMode then
        Thread.new {
          @client.sendCancelsEndGame(pieceIndex, offset, message.length - 8)
        }
      end
#      p "piece from #{self} piece: #{pieceIndex} offset #{offset}"
      @client.pieces[pieceIndex].writeData(offset, data)
    when "\x08"
      p "cancel from #{self}"
      # TODO
      # pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
      # offset = message[5..8].unpack("H*")[0].to_i(16)
      # length = message[9..12].unpack("H*")[0].to_i(16)
      # index = @pieces.index { |request| 
      #   request.pieceIndex == pieceIndex &&
      #   request.offset == offset &&
      #   request.length == length
      # }
      # @pieces.delete_at(index) if index != nil
    when "\x09"
#      p "port from #{self}"
    end
  end
end