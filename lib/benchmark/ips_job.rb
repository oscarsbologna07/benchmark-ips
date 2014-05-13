module Benchmark
  class IPSJob

    VERSION = "1.1.0"

    class Entry
      def initialize(label, action)
        @label = label

        if action.kind_of? String
          compile action
          @action = self
          @as_action = true
        else
          unless action.respond_to? :call
            raise ArgumentError, "invalid action, must respond to #call"
          end

          @action = action

          if action.respond_to? :arity and action.arity > 0
            @call_loop = true
          else
            @call_loop = false
          end

          @as_action = false
        end
      end

      attr_reader :label, :action

      def label_rjust
        if @label.size > 20
          "#{item.label}\n#{' ' * 20}"
        else
          @label.rjust(20)
        end
      end


      def as_action?
        @as_action
      end

      def call_times(times)
        return @action.call(times) if @call_loop

        act = @action

        i = 0
        while i < times
          act.call
          i += 1
        end
      end

      def compile(str)
        m = (class << self; self; end)
        code = <<-CODE
          def call_times(__total);
            __i = 0
            while __i < __total
              #{str};
              __i += 1
            end
          end
        CODE
        m.class_eval code
      end
    end

    attr_accessor :warmup, :time

    def initialize opts={}
      @suite = opts[:suite] || nil
      @quiet = opts[:quiet] || false
      @list = []
      @compare = false

      # defaults
      @warmup = 2
      @time = 5
    end

    def config opts
      @warmup = opts[:warmup] if opts[:warmup]
      @time = opts[:time] if opts[:time]
    end

    # An array of 2-element arrays, consisting of label and block pairs.
    attr_reader :list

    # Boolean determining whether to run comparison utility
    attr_reader :compare

    def compare?
      @compare
    end

    def compare!
      @compare = true
    end

    #
    # Registers the given label and block pair in the job list.
    #
    def item(label="", str=nil, &blk) # :yield:
      if blk and str
        raise ArgumentError, "specify a block and a str, but not both"
      end

      action = str || blk
      raise ArgumentError, "no block or string" unless action

      @list.push Entry.new(label, action)
      self
    end
    alias_method :report, :item

    def warmup
      timing = {}
      @list.each do |item|
        @suite.warming item.label, @warmup if @suite

        unless @quiet
          $stdout.printf item.label_rjust
        end

        Timing.clean_env

        before = Time.now
        target = Time.now + @warmup

        warmup_iter = 0

        while Time.now < target
          item.call_times(1)
          warmup_iter += 1
        end

        after = Time.now

        warmup_time = (after.to_f - before.to_f) * 1_000_000.0

        # calculate the time to run approx 100ms

        cycles_per_100ms = ((100_000 / warmup_time) * warmup_iter).to_i
        cycles_per_100ms = 1 if cycles_per_100ms <= 0

        timing[item] = cycles_per_100ms

        $stdout.printf "%10d i/100ms\n", cycles_per_100ms unless @quiet

        @suite.warmup_stats warmup_time, cycles_per_100ms if @suite
      end
      timing
    end

    def run timing
      reports = []

      @list.each do |item|
        @suite.running item.label, @time if @suite

        unless @quiet
          $stdout.print item.label_rjust
        end

        Timing.clean_env

        iter = 0

        target = Time.now + @time

        measurements = []

        cycles_per_100ms = timing[item]

        while Time.now < target
          before = Time.now
          item.call_times cycles_per_100ms
          after = Time.now

          # If for some reason the timing said this too no time (O_o)
          # then ignore the iteration entirely and start another.
          #
          m = ((after.to_f - before.to_f) * 1_000_000.0)
          next if m <= 0.0

          iter += cycles_per_100ms

          measurements << m
        end

        measured_us = measurements.inject(0) { |a,i| a + i }

        all_ips = measurements.map { |i| cycles_per_100ms.to_f / (i.to_f / 1_000_000) }

        avg_ips = Timing.mean(all_ips)
        sd_ips =  Timing.stddev(all_ips).round

        rep = create_report(item, measured_us, iter, avg_ips, sd_ips, cycles_per_100ms)

        $stdout.puts " #{rep.body}" unless @quiet

        @suite.add_report rep, caller(1).first if @suite

        reports << rep
      end
      reports
    end

    def create_report(item, measured_us, iter, avg_ips, sd_ips, cycles_per_100ms)
      IPSReport.new(item.label, measured_us, iter, avg_ips, sd_ips, cycles_per_100ms)
    end

  end
end
