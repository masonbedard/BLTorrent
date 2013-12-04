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
          handshake = peer.socket.recv 68
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

      ready, = IO.select(fds, nil, nil, 5)
      if ready.nil? then
        next
      end
      ready.each do |fd|
        puts "#{@peers[@peers.index { |peer| peer.socket == fd}]}"
        len = fd.recv(4).unpack("H*")[0].to_i(16) # find length of message
        message = fd.recv(len)
        puts "Length: #{len} got: #{message.length}"
        puts message
      end
    end
  end
end