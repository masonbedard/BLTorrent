require './metainfo'
require 'socket'
require './event'

def genPiecesArray(pieceLength, numPieces) 
    pieces = Array.new(numPieces)
    i = 0
    while (i < numPieces)
        pieces[i] = Piece.new(pieceLength)
        i += 1
    end
    return pieces
end

class Client
  include Event

  event :peerConnected, :peerTimeout, :peerDisconnect

  def initialize(metainfo)
    @metainfo = metainfo
    @rarity = {}
    @peerId = "BLT--#{Time::now.to_i}--#{Process::pid}BLT"[0...20]
    @pieces = genPiecesArray(@metainfo.pieceLength, @metainfo.pieces.size)
    p "done"
    response = Comm::makeTrackerRequest(@metainfo.announce,@metainfo.infoHash, @peerId)
    @peers = Metainfo::parseTrackerResponse(response)
    puts "Num peers: #{@peers.length}"
    on_event(self, :peerConnected) do |c, peer| 
      puts "connected to: #{peer}\n"
    end
    on_event(self, :peerTimeout) do |c, peer| 
      p "Unable to connect to: #{peer}\n"
      connectToPeer
    end
    on_event(self, :peerDisconnect) do |c, peer, reason| 
      p "Peer removed: #{peer} #{reason}\n"
      peer.socket.close
      peer.connected = false
      connectToPeer
    end
    1.times { connectToPeer }
    talkToPeers
  end

  def connectToPeer
    @peers.each do |peer|
      next if peer.connected or peer.tried
      peer.tried = true
      Thread.new do
        begin
          Timeout::timeout(5) {
            peer.socket = TCPSocket.new(peer.ip, peer.port)
            Comm::sendHandshake(peer, @metainfo.infoHash, @peerId)
            handshake = peer.socket.read 68
            peer.commRecv = Time.now
            #TODO add check for info hash
            peer.connected = true
            send_event(:peerConnected, peer)
          }
        rescue Errno::ETIMEDOUT, Timeout::Error
          send_event(:peerTimeout, peer)
        end
      end
      break
    end
  end

  def talkToPeers
    while true do # Change to make sure there is data to download eventually....
      fds = @peers.shuffle.select { |peer| peer.connected }.map { |peer| peer.socket }
      puts 
      puts "Peers connected: #{fds.length}" if true#(rand *100)%100 > 90
      fds.each { |fd|
        if fd.closed? then
          puts "Closed"
        end
      }
      ready, = IO.select(fds, nil, nil, 1)
      if not ready.nil? then
        ready.each do |fd|
          peerIndex = @peers.index { |peer| peer.socket == fd }
          peer = @peers[peerIndex]
          puts "#{peer}"
          peer.commRecv = Time.now
          data = fd.recv(4)# find length of message
          if data.nil? or data.empty? then
            send_event(:peerDisconnect, peer, "Peer closed connection")
            next
          end
          len = data.unpack("H*")[0].to_i(16)
          if len > 0 then
            message = ""
            begin
              while message.length < len
                Timeout::timeout(3) {
                  data = fd.recv(len - message.length)
                  if data.nil? or data.empty? then
                    send_event(:peerDisconnect, peer, "Didnt recv full message")
                    next
                  end
                  message.concat data
                }
              end 
              puts "Length: #{len} got: #{message.length}"
              parseMessage(message, peerIndex, len)
            rescue Timeout::Error
              send_event(:peerDisconnect, peer, "Timeout while getting data")
            end
          else 
            puts "Data: #{data} nil? #{data.nil?}"
            puts "Got keep alive #{Time.now} Len: #{len} Closed: #{fd.closed?}"
          end
        end
      end
      # i = 0
      # while (i < @pieces.length)
      #   piece = @pieces[i]
      #   if not piece.complete? then
      #     peers_with_piece = @peers.select { |peer| peer.connected && peer.pieces[i] && (not peer.didRequest) }
      #     #p "peers with piece: #{peers_with_piece.length}"
      #     peers_with_piece.each { |peer|
      #       if not peer.am_interested then
      #         Comm::sendMessage(peer, "interested")
      #         p "***********Sending interested to #{peer.to_s}"
      #         peer.am_interested = true
      #       end
      #       if not peer.is_choking then
      #         Comm::sendMessage(peer, "request", i, 0)
      #         peer.didRequest = true
      #       end
      #     }
      #   end
      #   i = i+1
      # end
      @peers.each { |peer| # disconnect if nothing recv
        if peer.connected && Time.now-120 > peer.commRecv then
          send_event(:peerDisconnect, peer, "No connectivity seen")
        end
      }
      @peers.each { |peer| # send keep alives
        if peer.connected && Time.now-110 > peer.commSent then
          Comm.sendMessage(peer, "keep-alive")
        end
      }
    end
  end

   def parseMessage(message, peerIndex, length)
    case message[0]
    when "\x00"
      p "choke"
      @peers[peerIndex].is_choking = true
    when "\x01"
      p "unchoke"
      @peers[peerIndex].is_choking = false
    when "\x02"
      p "interested"
      @peers[peerIndex].is_interested = true
    when "\x03"
      p "not interested"
      @peers[peerIndex].is_interested = false
    when "\x04"
      p "have"
      pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
      if @rarity.nil? then
        @rarity[pieceIndex] = []
      end
      @rarity[pieceIndex].push(@peers[peerIndex])
      #p pieceIndex
    when "\x05"
      p "bitfield"
      i = 1
      bitmap = ""
      while (i < length) 
        #p "byte number #{i}"
        #p message[i]
        #p message[i].unpack("H*")[0].to_i(16).to_s(2)
        bitmap += message[i].unpack("H*")[0].to_i(16).to_s(2)
        i += 1
      end
      bitmapLen = bitmap.length
      i = 0
      while (i < bitmapLen)
        if bitmap[i] == "1"
          if @rarity[i].nil? then
            @rarity[i] = []
          end
          @rarity[i].push(@peers[peerIndex])
        end
        i += 1
      end
    when "\x06"
      p "request"
      pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
      offset = message[5..8].unpack("H*")[0].to_i(16)
      length = message[9..12].unpack("H*")[0].to_i(16)
      @peers[peerIndex].requests.unshift(Request.new(pieceIndex, offset, length))
    when "\x07"
      p "piece"
      pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
      offset = message[5..8].unpack("H*")[0].to_i(16)
      data = message[6..message.length]
      @pieces[pieceIndex].writeData(offset, data)
    when "\x08"
      p "cancel"
      pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
      offset = message[5..8].unpack("H*")[0].to_i(16)
      length = message[9..12].unpack("H*")[0].to_i(16)
      index = @pieces.index { |request| 
        request.pieceIndex == pieceIndex &&
        request.offset == offset &&
        request.length == length
      }
      @pieces.delete_at(index) if index != nil
    when "\x09"
      p "port"
    end
  end

  def getRarestPiece #TODO
    @pieces.select {|piece| not piece.complete? }[0]
  end
end
