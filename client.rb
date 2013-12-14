require './metainfo'
require './event'
require './filemanager'
require './tracker'
require './piece'

require 'socket'

class Client
  include Event

  attr_accessor :rarity, :peers, :pieces, :fm, :metainfo, 
                :peerId, :uploadedBytes, :downloadedBytes, 
                :endGameMode, :bytesInInterval

  event :peerConnect, :peerTimeout, :peerDisconnect, :pieceValid, :pieceInvalid, :complete

  def initialize(metainfo)
    @complete = false
    @piecesDownloaded = 0
    @currentPieces = []
    @desiredPieces = []
    @endGamePieces = {}
    @endGameMode = false
    @metainfo = metainfo
    @timeOfLastChokeAlgorithm = Time.now
    @mutex = Mutex.new
    @peersToUploadTo = []
    @numConnectedPeers = 0
    @roundsSinceLastTime = 0
    @rarity = {}
    @peerId = "BLT--#{Time::now.to_i}--#{Process::pid}BLT"[0...20]
    @pieces = genPiecesArray(@metainfo.pieceLength, @metainfo.pieces.size)
    @fm = FileManager.new(self)
    @peers = []
    @downloadedBytes = 0
    @uploadedBytes = 0
    @bytesInInterval = 0
    @lastInterval = Time.now
    @tracker = Tracker.new(self)
    @tracker.makeRequest(:started)
    @listenThread = Thread.new {
      listenForPeers
    }
    p "#{@metainfo}"
    puts "Num peers: #{@peers.length}"
    on_event(self, :peerConnect) do |c, peer| 
      puts "connected to: #{peer}\n"
    end
    on_event(self, :peerTimeout) do |c, peer| 
      p "Timeout connecting to: #{peer}\n"
      connectToPeer
    end
    on_event(self, :peerDisconnect) do |c, peer, reason| 
#      p "Peer removed: #{peer} #{reason}\n"
      peer.connected = false
      peer.blacklisted = true
      peer.socket.close
      peer.clearRequests    # added this
      chokeAlgorithm
      connectToPeer
    end
    on_event(self, :pieceValid) do |c, piece|
#      p "Valid piece: #{@pieces.index(piece)}"
      @downloadedBytes+=@metainfo.pieceLength
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
    totalBytes = @metainfo.files.inject(0) {|sum, arr| sum + arr[1]}
    count = 0
    pieces = Array.new(numPieces)
    i = 0
    while (count < totalBytes)
      pieces[i] = Piece.new(self, [pieceLength,totalBytes-count].min, @metainfo.pieces[i])
      i += 1
      count += pieceLength
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

  def sendCancelsEndGame(pieceIndex, offset, length)
    for peer in @peers
      for request in peer.requestsToTimes do
        if request[0] == pieceIndex && request[1] == offset then
          peer.requestsToTimes.delete(request)
          peer.sendMessage(:cancel, pieceIndex, offset, length)
          break
        end
      end
    end
  end


=begin

  def chokeAlgorithm

    @roundsSinceLastTime += 1

    @peersToUploadTo = []

    interestedUploaders = @peers.select{|peer|
      !peer.is_seeder && peer.is_interested && peer.connected
    }

    if interestedUploaders.nil?
      return
    end

    sortedInterestedUploaders = interestedUploaders.sort{ |x,y|
      xRollingAverage = x.rollingAverage.inject(:+) / x.rollingAverage.size
      yRollingAverage = y.rollingAverage.inject(:+) / y.rollingAverage.size
      xRollingAverage <=> yRollingAverage
    }

    while @peersToUploadTo.size < 4 && !sortedInterestedUploaders.empty?)
      @peersToUploadTo.push(sortedInterestedUploaders.pop)
    end

    if !roundsSinceLastTime >= 3
      optimisticOptions = sortedInterestedUploaders.shuffle

      while @peersToUploadTo.size < 5 && !optimisticOptions.empty?
        @peersToUploadTo.push(optimisticOptions.pop)
      end
      @roundsSinceLastTime = 0
    end

    @timeOfLastChokeAlgorithm = Time.now

  end
=end

  #probably need a mutex on this function actually
  #listen on http advertised port
  #deal with sending interesteds

  def chokeAlgorithm
    p "calle dchoke"
    @mutex.synchronize {

      @roundsSinceLastTime += 1

      if @roundsSinceLastTime < 3 then
        @timeOfLastChokeAlgorithm = Time.now
        return
      end

      newestUnchokedPeers = []

      interestedUploaders = @peers.select{ |peer|
        !peer.is_seeder && peer.is_interested && peer.connected && Time.now - peer.timeOfLastBlockFrom < 60
      }

      if !interestedUploaders.nil? then

        sortedInterestedUploaders = interestedUploaders.sort{ |x,y|
          xRollingAverage = x.rollingAverage.inject(:+) / x.rollingAverage.size
          yRollingAverage = y.rollingAverage.inject(:+) / y.rollingAverage.size
          xRollingAverage <=> yRollingAverage
        }

        while (newestUnchokedPeers.size < 4 && !sortedInterestedUploaders.empty?)
          newestUnchokedPeers.push(sortedInterestedUploaders.pop)
        end

      end

      optimisticOptions = @peers.select { |peer|
        !peer.is_seeder && !newestUnchokedPeers.include?(peer) && peer.connected && Time.now - peer.timeOfLastBlockFrom < 60
      }

      if optimisticOptions != nil then
        optimisticOptions.shuffle!
        for option in optimisticOptions do
          newestUnchokedPeers.push(option)
          if newestUnchokedPeers.size > 4 then
            if option.is_interested
              break
            end
          end
        end
      end

      stayingUnchoked = newestUnchokedPeers & @peersToUploadTo

      for peer in @peersToUploadTo
        if !stayingUnchoked.include?(peer)
          peer.send_event(:stopAnswer)
        end
      end

      for peer in newestUnchokedPeers
        if !stayingUnchoked.include?(peer)
          peer.send_event(:answer)
        end
      end

      @peersToUploadTo = newestUnchokedPeers

      @timeOfLastChokeAlgorithm = Time.now
      @roundsSinceLastTime = 0

    }

  end

  # added this
  def setUpEndGame
    i = 0
    piecesLen = @pieces.size
    while i < piecesLen
      if @pieces[i] == nil then
        i += 1
        next
      end
      if !@pieces[i].verified then
        for offset in @pieces[i].requested.keys
          if @pieces[i].requested[offset] == nil then
            next
          end
          length = @pieces[i].requested[offset][0]
          if @endGamePieces[i] == nil then
            @endGamePieces[i] = []
          end
          @endGamePieces[i].push([offset, length])
        end
      end
      i += 1
    end
  end

  def keepTrackOfAverage(peer)
    peer.rollingAverage.unshift(peer.bytesFromThisSecond)
    if (peer.rollingAverage.size > 20) then
      peer.rollingAverage.pop
    end
    peer.bytesFromThisSecond = 0;
    peer.timeOfLastAverage = Time.now
  end

  def talkToPeers

    while true do
      connected = 0
      connecting = 0
      blacklisted = 0
      @peers.each { |p|
        connected += 1 if p.connected
        connecting += 1 if p.connecting
        blacklisted += 1 if p.blacklisted
      }
      if connected + connecting + blacklisted == @peers.length then
        if connected + connecting < 30 && Time.now - @tracker.lastRequest > @tracker.minInterval then
          p "Need more peers, sending request"
          @tracker.makeRequest
          p "new peers length #{@peers.length}"
        end
      else
        (30 - (connected + connected)).times { connectToPeer }
      end


      piecesLeft = @pieces.select { |p| p.verified == false }.length
      if piecesLeft == 0 && !@complete then
        @complete = true
        send_event(:complete)
      end
      if Time.now - @lastInterval > 1 then
        puts
        puts "There are #{piecesLeft} pieces left"
        puts "Download speed MB/s #{@bytesInInterval/1000000.0}"
        puts "Connected to #{@peers.select {|p| p.connected}.length} peers"
        puts
        @lastInterval = Time.now
        @bytesInInterval = 0
      end

      if Time.now - @tracker.lastRequest > @tracker.interval then
        @tracker.makeRequest
      end

      # SENDING #######################################################################

      if Time.now - @timeOfLastChokeAlgorithm > 10 then
        chokeAlgorithm
      end

      #do we do this every loop iteration?
      #how many of their requests should we answer?
=begin
      for peer in @peersToUploadTo do
        for request in peer.requestsFrom
          
        end
      end      
=end

      # SENDING #######################################################################

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

          if Time.now - peer.timeOfLastAverage > 1 then
            keepTrackOfAverage(peer)
          end

          if Time.now - 120 > peer.commRecv then #disconnect if nothing received for over 2 minutes
            peer.send_event(:noActivity)
          elsif Time.now - 110 > peer.commSent then #send keep alive if you havent sent to them in almost 2 minutes
            peer.sendMessage(:keepalive)
          end

          if !peer.is_choking then
#            p 'not choking'

            foundSomethingToRequest = false

            for time in peer.requestsToTimes
              if Time.now - time[0] > 60 then
                peer.disconnect "Timeout receiving data!"
              end 
            end

            # check end game here
            if @endGameMode then
              for pieceIndex in @endGamePieces.keys
                if peer.havePieces.include?(pieceIndex)
                  for block in @endGamePieces[pieceIndex]
                    alreadyRequested = false
                    for requestTo in peer.requestsToTimes
                      if requestTo[1] == pieceIndex && requestTo[2] == block[0] then
                        alreadyRequested = true
                        break
                      end
                    end
                    if !alreadyRequested then
#                      p "END GAME REQUEST _________ ----------___________---------"
                      peer.sendMessage(:request, pieceIndex, block[0], block[1])
                    end
                  end
                end
              end
              next
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
                  if !foundSomethingToRequest 
                    foundSomethingToRequest = true
                  end
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
                  if !foundSomethingToRequest
                    foundSomethingToRequest = true
                  end
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
                  if !foundSomethingToRequest
                    foundSomethingToRequest = true
                  end
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

            if !foundSomethingToRequest then
              p "ENTERING END GAME MODE BITCH BITCH BITCH BITCH BITCH BITCH BITCH"
              setUpEndGame
              @endGameMode = true
            end
          end
        end
      }
      sleep 0.01
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
    @tracker.makeRequest(:stopped)
  end

  def listenForPeers
    server = TCPServer.new 51415
    loop do
      client = server.accept
      begin
        Timeout::timeout(20) {
          x, port, x, ip = client.peeraddr
          data = client.recv(68)
          if data[28...48] != @metainfo.infoHash then
            p "bad info hash"
            client.close
          else
            p "got handshake"
            p "g903468-02835904-accepted #{ip} #{port}"
            peer = Peer.new(self, ip, port)
            peer.commRecv = Time.now
            peer.socket = client
            puts "send bitfield"
            peer.sendHandshakeNoRecv(@metainfo.infoHash, @peerId)
            peer.sendMessage(:bitfield)
            @peers.push(peer)
          end
        }
      rescue Timeout::Error
        next
      end
    end
  end
end
