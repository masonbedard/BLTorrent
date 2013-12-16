require './client.rb'
require './event'

begin

Thread.abort_on_exception = true
port = 51415
threads = []
clients = []


for filename in ARGV
  metainfo = Metainfo::parseFile(filename)

  client = Client.new(metainfo, port)
  client.on_event(self, :complete) {
    # client.shutdown!
    puts "Downloaded, seeding now"
  }
  t = Thread.new {
    client.start!
  }

  threads.push(t)
  clients.push(client)
  port += 1
end

threads.each {|t|t.join}

rescue Interrupt => e
  puts "Caught Interrupt..."
  clients.each { |c| c.shutdown! }
end