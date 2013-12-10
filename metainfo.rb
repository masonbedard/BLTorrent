# Represent metainfo that is stored in torrent file

require 'digest'
require './bencode.rb'
require './peer.rb'

class Metainfo
  attr_accessor :announce, :pieceLength, :pieces, :files, :infoHash, :torrentName

  def initialize(torrentName, announce, pieceLength, pieces, files, infoHash)
    @torrentName = torrentName
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

    infoHash = Digest::SHA1.digest(info.bencode)

    pieceLength = info["piece length"]
    pieces = info["pieces"].chars.each_slice(20).map(&:join)

    if info["files"] then # multiple files
      files = []
      info["files"].each { |f|
        path = f["path"].join()
        len = f["length"]
        files.push [path, len]
      }

    else # single file
      path = info["name"]
      len = info["length"]
      files = [[path, len]]
    end
    torrentName = filename.split("/")[-1]
    torrentName = torrentName[0..-9] if not torrentName.index(".torrent").nil?

    Metainfo.new(torrentName, announce, pieceLength, pieces, files, infoHash)
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
      result.push([ip, port])
      i += 6
    end
    return result
  end

  def to_s
    "Metainfo: <Tracker: #{@announce} Num pieces: #{@pieces.length}>"
  end
end

