require "net/http"
require "uri"

def getHex(number, padding)
  return [number.to_s(16).rjust(padding, '0')].pack("H*")
end

class Tracker
  attr_accessor :lastRequest, :interval
  def initialize(client)
    @client = client
    @lastRequest = nil
    @interval = -1
    @udpConnectionId = nil
  end

  def makeRequest(event=nil)
    case @client.metainfo.announce[0..4]
    when "udp:/"
      if @udpConnectionId.nil?
        udpConnect
      end
      udpAnnounce(event)
    when "http:"
      makeHTTPReq(event)
    else
      puts "unknown tracket type"
    end
  end

  def makeHTTPReq(event)
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
      parseHTTPResponse(res.body)
    else
      raise "Invalid response from tracker... #{@client.metainfo.announce}"
    end
  end

  def parseHTTPResponse(res)
    dict = BEncode::load(res)
    @interval = dict["interval"]
    if dict["peers"].class == Array then
      puts "No peers"
      return
    end
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

  def udpConnect
    connection_id = getHex(0x41727101980, 16)
    action = getHex(0, 8)
    transaction_id = getHex(rand(2**32),8)
    data = "#{connection_id}#{action}#{transaction_id}"

    uri = URI.parse(@client.metainfo.announce)
    sock = UDPSocket.new
    sock.connect(uri.host, uri.port)
    sock.send(data, 0)
    begin
      Timeout::timeout(5) {
        data = sock.recv 16
      }
    rescue Timeout::Error
      puts "Timeout connecting to tracker: #{@client.metainfo.announce}"
      return
    end
    
    if transaction_id != data[4...8] then
      puts "Tracker returned invalid id"
      return # tracker didnt send back corrent id
    end
    @udpConnectionId = data[8...16]
  end

  def udpAnnounce(event)
    action = getHex(1, 8)
    transaction_id = getHex(rand(2**32),8)
    info_hash = @client.metainfo.infoHash
    peer_id = @client.peerId
    downloaded = getHex(@client.downloadedBytes,16)
    uploaded = getHex(@client.uploadedBytes,16)
    left = getHex(@client.pieces.select {|p| !p.verified}.length * @client.metainfo.pieceLength,16)
    case event
    when :completed
      e = getHex(1,8)
    when :started
      e = getHex(2,8)
    when :stopped
      e = getHex(3,8)
    else
      e = getHex(0,8)
    end
    ip_address = getHex(0,8)
    key = getHex(0,8)
    num_want = getHex(50,8)
    port = getHex(51415, 4)
    data = "#{@udpConnectionId}#{action}#{transaction_id}#{info_hash}#{peer_id}"
    data.concat "#{downloaded}#{left}#{uploaded}#{e}#{ip_address}#{key}#{num_want}#{port}"
  
    uri = URI.parse(@client.metainfo.announce)
    sock = UDPSocket.new
    sock.connect(uri.host, uri.port)
    sock.send(data, 0)
    if event == :stopped
      return
    end
    begin
      Timeout::timeout(5) {
        data = sock.recv 320 # header(20) + ip&port(6)*50 
      }
    rescue Timeout::Error
      puts "Timeout connecting to tracker: #{@client.metainfo.announce}"
      return
    end
    if transaction_id != data[4...8] then
      puts "Tracker returned invalid id"
      return # tracker didnt send back corrent id
    end
    @interval = data[8...12].unpack("H*")[0].to_i
    peers = data[20..data.length].bytes
    i = 0
    while (i<peers.length) do
      ip = "#{peers[i]}.#{peers[i+1]}.#{peers[i+2]}.#{peers[i+3]}"
      port = peers[i+4] * 256 + peers[i+5]
      if @client.peers.select {|p| p.ip == ip && p.port==port}.length == 0 then
        @client.peers.push(Peer.new(@client, ip, port))
      end
      i += 6
    end

    @lastRequest = Time.now
  end
end