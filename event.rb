# allow events to be sent
# Adopted from rubytorrent-0.3

module Event
  def on_event(who, *events, &b)
    @event_handlers ||= Hash.new { [] }
    events.each do |e|
      raise ArgumentError, "unknown event #{e} for #{self.class}" unless (self.class.class_eval "@@event_has")[e]
      @event_handlers[e] <<= [who, b]
    end
    nil
  end

  def send_event(e, *args)
    raise ArgumentError, "unknown event #{e} for #{self.class}" unless (self.class.class_eval "@@event_has")[e]
    @event_handlers ||= Hash.new { [] }
    @event_handlers[e].each { |who, proc| proc[self, *args] }
    nil
  end

  def unregister_events(who, *events)
    @event_handlers.each do |event, handlers|
      handlers.each do |ewho, proc|
        if (ewho == who) && (events.empty? || events.member?(event))
          @event_handlers[event].delete [who, proc]
        end
      end
    end
    nil
  end

  def relay_event(who, *events)
    @event_handlers ||= Hash.new { [] }
    events.each do |e|
      raise "unknown event #{e} for #{self.class}" unless (self.class.class_eval "@@event_has")[e]
      raise "unknown event #{e} for #{who.class}" unless (who.class.class_eval "@@event_has")[e]
      @event_handlers[e] <<= [who, lambda { |s, *a| who.send_event e, *a }]
    end
    nil
  end

  def self.append_features(mod)
    super(mod)
    mod.class_eval %q{
      @@event_has ||= Hash.new(false)
      def self.event(*args)
        args.each { |a| @@event_has[a] = true }
      end
    }
  end
end