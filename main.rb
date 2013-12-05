require './client.rb'
require './metainfo.rb'
require './comm.rb'
require './peer.rb'
require './event'
require './piece.rb'
require './request.rb'

filename = ARGV[0]
 
metainfo = Metainfo::parseFile(filename)

client = Client.new(metainfo)

# IN MAIN FILE NEED TO CALCULATE LENGTH OF ALL FILES
# to pass into the make tracker requesst thing
