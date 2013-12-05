class Piece
    attr_accessor :data
    def initialize(pieceLength)
        @data = "0" * pieceLength
    end
end