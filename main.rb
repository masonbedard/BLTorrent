require './client.rb'
require './metainfo.rb'
require './httpComm.rb'
require './peer.rb'

filename = ARGV[0]

metainfo = Metainfo::parseFile(filename)
puts metainfo.to_s

client = Client.new(metainfo)


# IN MAIN FILE NEED TO CALCULATE LENGTH OF ALL FILES
# to pass into the make tracker requesst thing
