require './metainfo'
require 'socket'
require './event'

class Client
  include Event

  event :peerConnect, :peerTimeout, :peerDisconnect

  def initialize(metainfo)
    @metainfo = metainfo
    @rarity = {}
    @peerId = "BLT--#{Time::now.to_i}--#{Process::pid}BLT"[0...20]
    @pieces = genPiecesArray(@metainfo.pieceLength, @metainfo.pieces.size)
    p "#{@metainfo}"
    response = Comm::makeTrackerRequest(@metainfo.announce,@metainfo.infoHash, @peerId)
    ips = Metainfo::parseTrackerResponse(response)
    @peers = []
    ips.each {|ip|
      @peers.push(Peer.new(self, ip[0], ip[1]))
    }
    puts "Num peers: #{@peers.length}"
    on_event(self, :peerConnect) do |c, peer| 
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
    10.times { connectToPeer }
    talkToPeers
  end

  def genPiecesArray(pieceLength, numPieces) 
    pieces = Array.new(numPieces)
    i = 0
    while (i < numPieces)
      pieces[i] = Piece.new(pieceLength, @metainfo.pieces[i])
      i += 1
    end
    return pieces
  end

  def connectToPeer
    @peers.shuffle.each do |peer|
      next if peer.connected or peer.blacklisted or peer.connecting
      peer.sendHandshake(@metainfo.infoHash, @peerId)
      break
    end
  end

  def talkToPeers
    while true do # Change to make sure there is data to download eventually....

      @peers.each { |peer| # disconnect if nothing recv in past 2 minutes
        if peer.connected && Time.now-120 > peer.commRecv then
          p "time"
          peer.send_event(:noActivity)
        end
      }
      @peers.each { |peer| # send keep alives
        if peer.connected && Time.now-110 > peer.commSent then
          peer.sendMessage(:keepalive)
        end
      }
    end
  end
end
