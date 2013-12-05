class Piece
  attr_reader :data
  def initialize(pieceLength)
    @pieceLength = pieceLength
    @data = "0" * pieceLength
    @marked = {}
    @verified = false
  end

  def writeData(offset, data)
    @data[offset...(offset + data.length)] = data
    i = offset
    while i < (offset + data.length)
      @marked[i] = true
      i = i + 1
    end
  end

  def complete?
    @marked.keys.length == @pieceLength and @marked.key(false).nil?
  end

  def reset!
    @data = "0" * pieceLength
    @marked = [false] * pieceLength
  end

  def valid?(hash)
    return true if verified
    d = Digest::SHA1.digest @data

    if hash == d then
      verified = true
      true
    else 
      false
    end 
  end
end