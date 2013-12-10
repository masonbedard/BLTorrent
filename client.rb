require './metainfo'
require 'socket'
require './event'
require './filemanager'

class Client
  include Event

  attr_accessor :rarity, :peers, :pieces, :fm, :metainfo

  event :peerConnect, :peerTimeout, :peerDisconnect, :pieceValid, :pieceInvalid, :complete

  def initialize(metainfo)
    @piecesDownloaded = 0
    @currentPieces = []
    @desiredPieces = []
    @metainfo = metainfo
    @timeOfLastChokeAlgorithm = Time.now
    @peersToUploadTo = []
    @roundsSinceLastTime = 0
    @rarity = {}
    @peerId = "BLT--#{Time::now.to_i}--#{Process::pid}BLT"[0...20]
    @pieces = genPiecesArray(@metainfo.pieceLength, @metainfo.pieces.size)
    @fm = FileManager.new(self)
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
      chokeAlgorithm
      connectToPeer
    end
    on_event(self, :pieceValid) do |c, piece|
      p "Valid piece: #{@pieces.index(piece)}"
      @piecesDownloaded+=1
      pieceIndex = @pieces.index(piece)
      if @desiredPieces.include?(pieceIndex) then
        @desiredPieces.delete(pieceIndex)
      elsif @currentPieces.include?(pieceIndex) then
        @currentPieces.delete(pieceIndex)
      end
      offset = @pieces.index(piece) * @metainfo.pieceLength
      data = piece.data
      @fm.write(data, offset)
      @peers.each { |peer|
        if peer.connected then
          index = @pieces.index(piece)
          peer.sendMessage(:have, index)
        end
      }
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

  #probably need a mutex on this function actually
  #listen on http advertised port
  #deal with sending interesteds
  def chokeAlgorithm

    @roundsSinceLastTime += 1

    if @roundsSinceLastTime < 3 then
      return
    end

    @peersToUploadTo = []

    interestedUploaders = @peers.select{ |peer|
      !peer.is_seeder && peer.is_interested && peer.bytesFromSinceLastChoking > 0
    }

    sortedInterestedUploaders = interestedUploaders.sort{ |x, y|
      x.bytesFromSinceLastChoking <=> y.bytesFromSinceLastChoking
    }

    while (@peersToUploadTo.size < 3 && !sortedInterestedUploaders.empty?)
      @peersToUploadTo.push(sortedInterestedUploaders.pop)
    end

    optimisticOptions = @peers.select {|peer|
      !peer.is_seeder && !@peersToUploadTo.include?(peer)
    }

    optimisticOptions.shuffle!

    if optimisticOptions != nil then
      for option in optimisticOptions do
        @peersToUploadTo.push(option)
        if @peersToUploadTo.size > 3 then
          if option.is_interested
            break
          end
        end
      end
    end

    @timeOfLastChokeAlgoritm = Time.now
    @roundsSinceLastTime = 0

  end

  def talkToPeers
    while true do
      if @pieces.select { |p| p.verified == false }.length == 0 then
        send_event(:complete)
        break
      end
      if Time.now - @timeOfLastChokeAlgorithm > 10 then
        chokeAlgorithm
      end

      #do we do this every loop iteration?
      #how many of their requests should we answer?
      for peer in @peersToUploadTo do
        for request in peer.requestsFrom
        end
      end      
      # requesting to others
      if @piecesDownloaded > 4 && @desiredPieces.size < 10 then
        sortedRareIndices = @rarity.keys.sort { |x,y|
          @rarity[x].size <=> @rarity[y].size 
        }
        for index in sortedRareIndices
          if @desiredPieces.size > 9 then
            break
          end
          if @rarity[index].size == 0 || @pieces[index].verified then
            next
          end
          if !@desiredPieces.include?(index) then
            @desiredPieces.push(index)
            if @currentPieces.include?(index) then
              @currentPieces.delete(index)
            end
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

            # Peer doesn't have blocks from pieces we're currently working on
            for pieceIndex in peer.havePieces
              if @pieces[pieceIndex].verified then
                next
              end
              while peer.requestsToTimes.size < 5
                offset, length = @pieces[pieceIndex].getSectionToRequest
                if !offset.nil? then
                  peer.sendMessage(:request, pieceIndex, offset, length)
                  if @currentPieces.include?(pieceIndex) then
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
  def shutdown!
    # tracker shutdown
    @fm.close
    @peers.each { |peer|
      if peer.connected then
        peer.disconnect "Client shutting down"
      end
    }
  end
end
