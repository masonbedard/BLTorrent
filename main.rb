require './metainfo.rb'
require './httpComm.rb'
require './peer.rb'

thing = Metainfo::parseFile('./torrents/debian-7.1.0-i386-DVD-1.iso.torrent')
peerId = '00000999990000099999'  # actually create this in here
# and store it where it needs to be
response = HttpComm::makeTrackerRequest(thing.announce,thing.infoHash, peerId)
peers = Metainfo::parseTrackerResponse(response)
p peers
#p response


# IN MAIN FILE NEED TO CALCULATE LENGTH OF ALL FILES
# to pass into the make tracker requesst thing