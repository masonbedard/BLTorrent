require './client.rb'
require './metainfo.rb'
require './comm.rb'
require './peer.rb'
require './event'
require './piece.rb'
require './request.rb'

Thread.abort_on_exception = true

filename = ARGV[0]

metainfo = Metainfo::parseFile(filename)

client = Client.new(metainfo)
begin
  client.start!
rescue Interrupt => e
  puts "here"
  client.fm.close
end

# IN MAIN FILE NEED TO CALCULATE LENGTH OF ALL FILES
# to pass into the make tracker requesst thing
