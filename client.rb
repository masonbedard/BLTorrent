require './metainfo'
require 'socket'
require './event'

class Client
  include Event

  event :peerConnected, :peerTimeout, :peerDisconnect

  def initialize(metainfo)
    @metainfo = metainfo
    @peerId = "BLT--#{Time::now.to_i}--#{Process::pid}BLT"[0...20]

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
    on_event(self, :peerDisconnect) do |c, peer| 
      p "Peer removed: #{peer}\n"
      peer.socket.close
      peer.connected = false
      connectToPeer
    end
    10.times { connectToPeer }
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
            Comm::sendHandshake(peer.socket, @metainfo.infoHash, @peerId)
            handshake = peer.socket.read 68
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
      puts "Peers connected: #{fds.length}" if true#(rand *100)%100 > 90
      fds.each { |fd|
        if fd.closed? then
          puts "Closed"
        end
      }
      ready, = IO.select(fds, nil, nil, 1)
      if ready.nil? then
        next
      end
      ready.each do |fd|
        peerIndex = @peers.index { |peer| peer.socket == fd }
        peer = @peers[peerIndex]
        puts "#{peer}"
        data = fd.recv(4)# find length of message
        if data.nil? or data.empty? then
          send_event(:peerDisconnect, peer)
          next
        end
        len = data.unpack("H*")[0].to_i(16)
        if len > 0 then
          message = ""
          begin
            while message.length < len
              Timeout::timeout(2) {
                data = fd.recv(len - message.length)
                if data.nil? or data.empty? then
                  send_event(:peerDisconnect, peer)
                  next
                end
                message.concat data
              }
            end 
            puts "Length: #{len} got: #{message.length}"
          rescue Timeout::Error
            send_event(:peerDisconnect, peer)
          end
          # puts message.unpack("H*")
          parseMessage(message, peerIndex, len)
        else 
          puts "Data: #{data} nil? #{data.nil?}"
          puts "Got keep alive #{Time.now} Len: #{len} Closed: #{fd.closed?}"
        end
      end
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
        @peers[peerIndex].pieces[pieceIndex] = true
        #p pieceIndex
    when "\x05"
        p "bitfield"
        i = 1
        bitmap = ""
        while (i < length) 
            p "piece number #{i}"
            p message[i].unpack("H*")[0].to_i(16).to_s(2)
            bitmap += message[i].unpack("H*")[0].to_i(16).to_s(2)
            i += 1
        end
        bitmapLen = bitmap.length
        i = 0
        while (i < bitmapLen)
            if bitmap[i] == "1"
                @peers[peerIndex].pieces[i] = true
            end
            i += 1
        end
        #p @peers[peerIndex].pieces
    when "\x06"
        p "request"
        pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
        offset = message[5..8].unpack("H*")[0].to_i(16)
        length = message[9..12].unpack("H*")[0].to_i(16)
        p pieceIndex
        p offset
        p length
    when "\x07"
        p "piece"
        pieceIndex = message[1..4].unpack("H*")[0].to_i(16)
        offset = message[5..8].unpack("H*")[0].to_i(16)
    when "\x08"
        p "cancel"
    when "\x09"
        p "port"
    end
end


end
