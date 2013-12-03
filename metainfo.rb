# Represent metainfo that is stored in torrent file

require 'digest'
require './bencode.rb'
require './peer.rb'

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

  def self.parseTrackerResponse(res)

    # DEAL WITH OTHER KEYS OF RESPONSE
    # LIKE INTERVAL AND MININTERVAL
    
    result = []
    dict = BEncode::load(res)
    peers = dict["peers"].bytes.to_a
    peersLen = peers.length
    i = 0
    while (i<peersLen) do
      ip = "#{peers[i]}.#{peers[i+1]}.#{peers[i+2]}.#{peers[i+3]}"
      port = peers[i+4] * 256 + peers[i+5]
      result.push(Peer.new(ip, port))
      i += 6
    end
    return result
  end
end

