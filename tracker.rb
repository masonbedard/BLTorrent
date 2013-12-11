require "net/http"
require "uri"

class Tracker
  attr_accessor :lastRequest, :interval
  def initialize(client)
    @client = client
    @lastRequest = nil
    @interval = -1

  end

  def makeRequest(event=nil)
    if event!=nil&&event!=:started&&event!=:stopped&&event!=:completed then
      throw "Invalid tracker event: #{event}"
    end
    uploaded = @client.uploadedBytes
    downloaded = @client.downloadedBytes
    
    uri = URI.parse(@client.metainfo.announce)
    params = {
      info_hash: @client.metainfo.infoHash,
      peer_id: @client.peerId,
      compact: 1,
      left: @client.pieces.select {|p| !p.verified}.length * @client.metainfo.pieceLength,
      uploaded: @client.uploadedBytes,
      downloaded: @client.downloadedBytes,
      numwant: 50,
      port: 51415,
    }
    params[:event] = event if not event.nil?

    uri.query = URI.encode_www_form(params)
    @lastRequest = Time.now
    res = Net::HTTP.get_response(uri)
    if event == :stopped then
      return
    elsif res.is_a?(Net::HTTPSuccess) then
      parseResponse(res.body)
    else
      raise "Invalid response from tracker... #{@client.metainfo.announce}"
    end
  end

  def parseResponse(res)
    dict = BEncode::load(res)
    @interval = dict["interval"]
    peers = dict["peers"].bytes.to_a
    peersLen = peers.length
    i = 0
    while (i<peersLen) do
      ip = "#{peers[i]}.#{peers[i+1]}.#{peers[i+2]}.#{peers[i+3]}"
      port = peers[i+4] * 256 + peers[i+5]
      if @client.peers.select {|p| p.ip == ip && p.port==port}.length == 0 then
        @client.peers.push(Peer.new(@client, ip, port))
      end
      i += 6
    end
  end
end