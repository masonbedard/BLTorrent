# Represent metainfo that is stored in torrent file

require 'digest'
require './bencode.rb'

class Metainfo
  attr_accessor :announce, :pieceLength, :pieces, :files, :infoHash

  def initialize(announce, pieceLength, pieces, files, infoHash)
    @announce = announce
    @pieceLength = pieceLength
    @pieces = pieces
    @files = files
    @infoHash = infoHash
  end

  def self.parseFile(filename)
    file = File.open(filename, "r")
    parser = BEncode::Parser.new file
    dict = parser.parse!

    announce = dict["announce"]

    info = dict["info"]

    pieceLength = info["piece length"]
    pieces = info["pieces"].chars.each_slice(20).map(&:join)

    if info["files"] then # multiple files
      files = info["files"]

      for f in files
        f["path"] = f["path"].join()
      end
    else # single file
      files = [{path: info["file"], length: info["length"]}]
    end

    infoHash = Digest::SHA1.digest(info.bencode)

    Metainfo.new(announce, pieceLength, pieces, files, infoHash)
  end
end

