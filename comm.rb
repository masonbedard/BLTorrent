#make the get request to the announce url
#and receive its response

require 'net/http'
require 'uri'

class Comm

    def self.makeTrackerRequest(announceUrl, infoHash, peerId);
        uri = URI.parse(announceUrl)
        params = Hash.new()
        params['info_hash'] = infoHash
        params['peer_id'] = peerId
        params['compact'] = '1'
        params['left'] = '1'
        params['uploaded'] = '0'
        params['downloaded'] = '0'
        params['numwant'] = '50'
        params['port'] = '6889'
        params['event'] = 'started'
        
        #consider compact = 0?

        uri.query = URI.encode_www_form(params)

        res = Net::HTTP.get_response(uri)
        if res.is_a?(Net::HTTPSuccess) then
            return res.body
        end
        return nil
    end

    def self.sendHandshake(socket, infoHash, peerId)
        data = "\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{infoHash}#{peerId}"
        socket.write data
    end
end

