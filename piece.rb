class Piece
  attr_reader :data
  def initialize(pieceLength, hash)
    @pieceLength = pieceLength
    @data = "0" * pieceLength
    @blocks = {}
    @requested = {}
    @verified = false
    @hash = hash
  end

  def writeData(offset, data)
    p "**************got data"
    @data[offset...(offset + data.length)] = data
    @blocks[offset] = data.length
    if complete? then
      valid?
    end
  end

  def complete?
    index = 0
    while i < @pieceLength 
      x = @blocks[i]
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

  def getSection
    offset = 0
    while @blocks[offset]
      offset += @blocks[offset]
    end
    n = @blocks.keys.sort.select {|x| x > offset}[0]
    if n.nil? then
      @requested[offset] = [2**14, Time.now]
      return offset, 2**14
    else
      @requested[offset] = [[n, 2**14].min, Time.now]
      return offset, [n-offset, 2**14].min
    end
  end
end