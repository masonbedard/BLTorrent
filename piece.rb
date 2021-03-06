class Piece
  attr_accessor :verified, :requested, :data
  def initialize(client, pieceLength, hash)
    @client = client
    @pieceLength = pieceLength
    @data = "0" * pieceLength
    @blocks = {}
    @requested = {}
    @verified = false
    @hash = hash
    @mutex = Mutex.new
    @hasAlreadyHappened = false
  end

  def writeData(offset, data)
    @mutex.synchronize {
      return if @verified
      @data[offset...(offset + data.length)] = data
      @blocks[offset] = data.length
      if complete? then
        if valid? then
          if !@hasAlreadyHappened
            @hasAlreadyHappened = true
            @client.send_event(:pieceValid, self)
          end
        else
          reset!
          @client.send_event(:pieceInvalid, self)
        end
      end
    }
  end

  def complete?
    return true if @verified
    index = 0
    while index < @pieceLength 
      x = @blocks[index]
      if x.nil?
        return false
      end
      index += x
    end
    return index == @pieceLength
  end

  def reset!
    @data = "0" * @pieceLength
    @blocks = {}
    @requested = {}
  end

  def valid?
    return true if @verified
    d = Digest::SHA1.digest @data

    if @hash == d then
      @verified = true
      true
    else 
      false
    end 
  end

  def getAllSectionsNotHad(os, sectionsToRequest)
    offset = os
    while @blocks[offset]
      offset += @blocks[offset]
    end
    if offset == @pieceLength then
      return sectionsToRequest
    end
    n = @blocks.keys.sort.select {|x| x > offset}[0]
    if n.nil? then
      desiredLength = [2**14, @pieceLength - offset].min
    else
      desiredLength = [2**14, n - offset].min
    end
    sectionsToRequest.push([offset, desiredLength])
    return getAllSectionsNotHad(offset + desiredLength, sectionsToRequest)
  end

  def getSectionToRequest
    offset = 0
    while @blocks[offset]
      offset += @blocks[offset]
    end
    # try changing this time for timeouts? 
    while (@requested[offset] && Time.now - @requested[offset][1] < 10) do 
      offset += @requested[offset][0]
      while @blocks[offset] do
        offset += @blocks[offset]
      end
    end
    if (offset == @pieceLength) then
      return nil
    end

    n = @blocks.keys.sort.select {|x| x > offset}[0]
    if n.nil? then
      desiredLength = [2**14, @pieceLength - offset].min
    else
      desiredLength = [2**14, n - offset].min
    end
    @requested[offset] = [desiredLength, Time.now]
    return offset, desiredLength
  end
end

