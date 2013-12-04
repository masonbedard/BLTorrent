require './metainfo'
require 'socket'
require './event'

class Client
  include Event

  event :peerConnected, :peerTimeout

  def initialize(metainfo)
    @metainfo = metainfo
    @peerId = "BLT--#{Time::now.to_i}--#{Process::pid}BLT"[0...20]

    response = Comm::makeTrackerRequest(@metainfo.announce,@metainfo.infoHash, @peerId)
    @peers = Metainfo::parseTrackerResponse(response)
    on_event(self, :peerConnected) do |c, peer| 
      puts "connected to: #{peer}\n"
    end
    on_event(self, :peerTimeout) do |c, peer| 
      p "Unable to connect to: #{peer}\n"
      connectToPeer
    end
    5.times { connectToPeer }
    talkToPeers
  end

  def connectToPeer
    @peers.each do |peer|
      next if peer.connected or peer.tried
      peer.tried = true
      Thread.new do
        begin
          peer.socket = TCPSocket.new(peer.ip, peer.port)
          Comm::sendHandshake(peer.socket, @metainfo.infoHash, @peerId)
          handshake = peer.socket.read 68
          #TODO add check for info hash
          peer.connected = true
          send_event(:peerConnected, peer)
        rescue Errno::ETIMEDOUT
          send_event(:peerTimeout, peer)
        end
      end
      break
    end
  end

  def talkToPeers
    while true do # Change to make sure there is data to download eventually....
      fds = @peers.select { |peer| peer.connected }.map { |peer| peer.socket }
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
        peer = @peers[@peers.index { |peer| peer.socket == fd}]
        puts "#{peer}"
        data = fd.read(4)# find length of message
        if data.nil?
          puts "Peer disconnected #{peer}"
          peer.connected = false
        end
        len = data.unpack("H*")[0].to_i(16)
        if len > 0 then
          message = fd.read(len)
          puts "Length: #{len} got: #{message.length}"
          puts message.unpack("H*")
        else 
          puts "Got keep alive #{Time.now} Len: #{len} Closed: #{fd.closed?}"
        end
      end
    end
  end
end