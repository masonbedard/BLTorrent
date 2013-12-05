#make the get request to the announce url
#and receive its response

require "net/http"
require "uri"

def getHex(number, padding)
  #p number.to_s(16)
  #p number.to_s(16).rjust(padding, '0')
  #p [number.to_s(16).rjust(padding, '0')].pack("H*")
  return [number.to_s(16).rjust(padding, '0')].pack("H*")
end

class Comm

    def self.makeTrackerRequest(announceUrl, infoHash, peerId);
        uri = URI.parse(announceUrl)
        params = Hash.new()
        params["info_hash"] = infoHash
        params["peer_id"] = peerId
        params["compact"] = "1"
        params["left"] = "1"
        params["uploaded"] = "0"
        params["downloaded"] = "0"
        params["numwant"] = "50"
        params["port"] = "6889"
        params["event"] = "started"
        
        #consider compact = 0?

        uri.query = URI.encode_www_form(params)
        res = Net::HTTP.get_response(uri)
        if res.is_a?(Net::HTTPSuccess) then
            return res.body
        end
        return nil
    end

    def self.sendHandshake(peer, infoHash, peerId)
        socket = peer.socket
        data = "\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{infoHash}#{peerId}"
        socket.write data
        peer.commSent = Time.now
    end

    def self.sendMessage(peer, message, first=nil, second=nil, third=nil)
        socket = peer.socket
        case message
        when "keep-alive"
            data = "\x00\x00\x00\x00"
        when "choke"
            data = "\x00\x00\x00\x01\x00"
        when "unchoke"
            data = "\x00\x00\x00\x01\x01"
        when "interested"
            data = "\x00\x00\x00\x01\x02"
        when "not interested"
            data = "\x00\x00\x00\x01\x03"
        when "have"
            data = "\x00\x00\x00\x05\x04"
            data += getHex(first, 8)
        when "bitfield"
            bitfield = "100100111"
            for piece in first
                if piece.possessed then
                    bitfield += "1"
                else
                    bitfield += "0"
                end
            end
            i = bitfield.size
            while (i % 8) != 0
                bitfield += "0"
                i += 1
            end
            bitfieldValue = bitfield.to_i(2)
            len = 1 + (bitfieldValue.to_s(16).size / 2)
            data = getHex(len, 8)
            data += "\x05"
            data += getHex(bitfieldValue, 0)
        when "request"
            data = "\x00\x00\x00\x0d\x06"
            data += getHex(first, 8)
            data += getHex(second, 8)
            data += getHex(16384, 8)
        when "piece"
            len = 9 + third.size
            data = getHex(len, 8)
            data += "\x07"
            data += getHex(first, 8)
            data += getHex(second, 8)
            data += getHex(third, 0)
        when "cancel"
            data = "\x00\x00\x00\x0d\x08"
            data += getHex(first, 8)
            data += getHex(second, 8)
            data += getHex(16384, 8)
        when "port"
            data = "\x00\x00\x00\x03\x09"
            data += getHex(first, 8)
        end
        #p data
        socket.write data
        peer.commSent = Time.now
    end


end

