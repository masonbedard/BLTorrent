require './client.rb'
require './event'

Thread.abort_on_exception = true

filename = ARGV[0]

metainfo = Metainfo::parseFile(filename)

client = Client.new(metainfo)
client.on_event(self, :complete) {
  client.shutdown!
  puts "Complete"
}
begin
  client.start!
rescue Interrupt => e
  puts "Shutting down..."
  client.shutdown! 
end

# IN MAIN FILE NEED TO CALCULATE LENGTH OF ALL FILES
# to pass into the make tracker requesst thing
