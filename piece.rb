class Piece
  attr_reader :data
  attr_accessor :verified
  def initialize(client, pieceLength, hash)
    @client = client
    @pieceLength = pieceLength
    @data = "0" * pieceLength
    @blocks = {}
    @requested = {}
    @verified = false
    @hash = hash
    @mutex = Mutex.new
  end

  def writeData(offset, data)
    @data[offset...(offset + data.length)] = data
    @blocks[offset] = data.length
    if complete? then
      if valid? then
        @client.send_event(:pieceValid, self)
      else
        reset!
        @client.send_event(:pieceInvalid, self)
      end
    end
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
    @mutex.synchronize {
      d = Digest::SHA1.digest @data

      if @hash == d then
        @verified = true
        true
      else 
        false
      end 
    }
  end

  def getSectionToRequest
    offset = 0
    while @blocks[offset]
      offset += @blocks[offset]
    end
    while (@requested[offset] && Time.now - @requested[offset][1] < 60) do 
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
      desiredLength = [2**15, @pieceLength - offset].min
    else
      desiredLength = [2**15, n - offset].min
    end
    @requested[offset] = [desiredLength, Time.now]
    return offset, desiredLength
  end
end

