require './metainfo.rb'
require 'socket'

class Client
  def initialize(metainfo)
    @metainfo = metainfo
    @peerId = "BLT--#{Time::now.to_i}--#{Process::pid}BLT"[0...20]

    response = HttpComm::makeTrackerRequest(@metainfo.announce,@metainfo.infoHash, @peerId)
    @peers = Metainfo::parseTrackerResponse(response)

    connectToPeers
  end

  def connectToPeers
    count = 0
    for peer in @peers
      puts peer.to_s
      if count > 5 then
        break
      end
      if peer.connected then
        continue
      end
      peer.socket = TCPSocket.new(peer.ip, peer.port)
      HttpComm::sendHandshake(peer.socket, @metainfo.infoHash, @peerId)
    end
  end

end