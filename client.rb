require './metainfo'
require 'socket'
require './event'
require './filemanager'

class Client
  include Event

  attr_accessor :rarity, :peers, :pieces, :fm

  event :peerConnect, :peerTimeout, :peerDisconnect, :pieceValid, :pieceInvalid

  def initialize(metainfo)
    @piecesDownloaded = 0
    @currentPieces = []
    @desiredPieces = []
    @metainfo = metainfo
    @rarity = {}
    @peerId = "BLT--#{Time::now.to_i}--#{Process::pid}BLT"[0...20]
    @pieces = genPiecesArray(@metainfo.pieceLength, @metainfo.pieces.size)
    @fm = FileManager.new(@metainfo.files)
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
      p "Timeout connecting to: #{peer}\n"
      connectToPeer
    end
    on_event(self, :peerDisconnect) do |c, peer, reason| 
      p "Peer removed: #{peer} #{reason}\n"
      peer.connected = false
      peer.socket.close
      connectToPeer
    end
    on_event(self, :pieceValid) do |c, piece|
      p "Valid piece: #{@pieces.index(piece)}"
      offset = @pieces.index(piece) * @metainfo.pieceLength
      data = piece.data
      @fm.write(data, offset)
    end
    on_event(self, :pieceInvalid) do |c, piece|
      p "Invalid piece: #{@pieces.index(piece)}"
    end
  end

  def start!
    30.times { connectToPeer }
    talkToPeers
  end

  def genPiecesArray(pieceLength, numPieces) 
    pieces = Array.new(numPieces)
    i = 0
    while (i < numPieces)
      pieces[i] = Piece.new(self, pieceLength, @metainfo.pieces[i])
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

      # might need to mess with this limit 10
      # im thinking that if you can make 5 requests to peers and we
      # might use 30 simultaneous peers for maximum
      # then you could potentially have 150 requests out at once
      # and if each piece is perhaps 256k and each block is 16kb
      # then having 10 desired pieces means 160ish blocks available to request
      if @piecesDownloaded > 4 && @desiredPieces.size < 10 then
        sortedRareIndices = @rarity.keys.sort { |x,y|
          @rarity[x].size <=> @rarity[y].size 
        }
        for index in sortedRareIndices
          if @desiredPieces.size > 4 then
            break
          end
          if !@desiredPieces.include?(index) then
            @desiredPieces.push(index)
          end
        end
      end

      @peers.each { |peer|
        if peer.connected then

          if Time.now-120 > peer.commRecv then #disconnect if nothing received for over 2 minutes
            peer.send_event(:noActivity)
          elsif Time.now - 110 > peer.commSent then #send keep alive if you havent sent to them in almost 2 minutes
            peer.sendMessage(:keepalive)
          end

          if !peer.is_choking then

            for time in peer.requestsToTimes
              if Time.now - time[0] > 60 then
                peer.requestsToTimes.delete(time)
              end 
            end

            if peer.requestsToTimes.size > 4 then
              next
            end

            for pieceIndex in @desiredPieces
              if peer.havePieces.index(pieceIndex).nil? then
                next
              end
              while peer.requestsToTimes.size < 5
                offset, length = @pieces[pieceIndex].getSectionToRequest
                if offset != nil then
                  peer.sendMessage(:request, pieceIndex, offset, length)  #increments peer.requestsToTimes
                else
                  break
                end
              end
              if peer.requestsToTimes.size > 4 then
                break
              end
            end

            if peer.requestsToTimes.size > 4 then
              next
            end

            for pieceIndex in @currentPieces
              if peer.havePieces.index(pieceIndex) == nil then
                next
              end
              while peer.requestsToTimes.size < 5
                offset, length = @pieces[pieceIndex].getSectionToRequest
                if offset != nil then
                  peer.sendMessage(:request, pieceIndex, offset, length)
                else
                  break
                end
              end
              if peer.requestsToTimes.size > 4 then
                break
              end
            end

            if peer.requestsToTimes.size > 4 then
              next
            end

            # Peer doesn't have 5 desired blocks, lets get at least 5
            for pieceIndex in peer.havePieces
              while peer.requestsToTimes.size < 5
                offset, length = @pieces[pieceIndex].getSectionToRequest
                if !offset.nil? then
                  peer.sendMessage(:request, pieceIndex, offset, length)
                  if @currentPieces.index(pieceIndex).nil? then
                    @currentPieces.push(pieceIndex)
                  end
                else
                  break
                end
              end
              if peer.requestsToTimes.size > 4 then
                break
              end
            end
          end
        end
      }
      sleep 0.5
    end
  end

end
