class Request
    attr_accessor :pieceIndex, :offset, :length
    def initialize(pieceIndex, offset, length)
        @pieceIndex = pieceIndex
        @offset = offset
        @length = length
    end
end