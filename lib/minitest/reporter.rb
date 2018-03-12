module Minitest
  ##
  # Defines the API for Reporters. Subclass this and override whatever
  # you want. Go nuts.

  class AbstractReporter
    include Mutex_m

    ##
    # Starts reporting on the run.

    def start
    end

    ##
    # About to start running a test. This allows a reporter to show
    # that it is starting or that we are in the middle of a test run.

    def prerecord klass, name
    end

    ##
    # Record a result and output the Runnable#result_code. Stores the
    # result of the run if the run did not pass.

    def record result
    end

    ##
    # Outputs the summary of the run.

    def report
    end

    ##
    # Did this run pass?

    def passed?
      true
    end
  end

  class Reporter < AbstractReporter # :nodoc:
    ##
    # The IO used to report.

    attr_accessor :io

    ##
    # Command-line options for this run.

    attr_accessor :options

    def initialize io = $stdout, options = {} # :nodoc:
      super()
      self.io      = io
      self.options = options
    end
  end

  ##
  # A very simple reporter that prints the "dots" during the run.
  #
  # This is added to the top-level CompositeReporter at the start of
  # the run. If you want to change the output of minitest via a
  # plugin, pull this out of the composite and replace it with your
  # own.

  class ProgressReporter < Reporter
    def prerecord klass, name #:nodoc:
      if options[:verbose] then
        io.print "%s#%s = " % [klass.name, name]
        io.flush
      end
    end

    def record result # :nodoc:
      io.print "%.2f s = " % [result.time] if options[:verbose]
      io.print result.result_code
      io.puts if options[:verbose]
    end
  end

  ##
  # A reporter that gathers statistics about a test run. Does not do
  # any IO because meant to be used as a parent class for a reporter
  # that does.
  #
  # If you want to create an entirely different type of output (eg,
  # CI, HTML, etc), this is the place to start.

  class StatisticsReporter < Reporter
    # :stopdoc:
    attr_accessor :assertions
    attr_accessor :count
    attr_accessor :results
    attr_accessor :start_time
    attr_accessor :total_time
    attr_accessor :failures
    attr_accessor :errors
    attr_accessor :skips
    # :startdoc:

    def initialize io = $stdout, options = {} # :nodoc:
      super

      self.assertions = 0
      self.count      = 0
      self.results    = []
      self.start_time = nil
      self.total_time = nil
      self.failures   = nil
      self.errors     = nil
      self.skips      = nil
    end

    def passed? # :nodoc:
      results.all?(&:skipped?)
    end

    def start # :nodoc:
      self.start_time = Minitest.clock_time
    end

    def record result # :nodoc:
      self.count += 1
      self.assertions += result.assertions

      results << result if not result.passed? or result.skipped?
    end

    def report # :nodoc:
      aggregate = results.group_by { |r| r.failure.class }
      aggregate.default = [] # dumb. group_by should provide this

      self.total_time = Minitest.clock_time - start_time
      self.failures   = aggregate[Assertion].size
      self.errors     = aggregate[UnexpectedError].size
      self.skips      = aggregate[Skip].size
    end
  end

  ##
  # A reporter that prints the header, summary, and failure details at
  # the end of the run.
  #
  # This is added to the top-level CompositeReporter at the start of
  # the run. If you want to change the output of minitest via a
  # plugin, pull this out of the composite and replace it with your
  # own.

  class SummaryReporter < StatisticsReporter
    # :stopdoc:
    attr_accessor :sync
    attr_accessor :old_sync
    # :startdoc:

    def start # :nodoc:
      super

      io.puts "Run options: #{options[:args]}"
      io.puts
      io.puts "# Running:"
      io.puts

      self.sync = io.respond_to? :"sync=" # stupid emacs
      self.old_sync, io.sync = io.sync, true if self.sync
    end

    def report # :nodoc:
      super

      io.sync = self.old_sync

      io.puts unless options[:verbose] # finish the dots
      io.puts
      io.puts statistics
      aggregated_results io
      io.puts summary
    end

    def statistics # :nodoc:
      "Finished in %.6fs, %.4f runs/s, %.4f assertions/s." %
        [total_time, count / total_time, assertions / total_time]
    end

    def aggregated_results io # :nodoc:
      filtered_results = results.dup
      filtered_results.reject!(&:skipped?) unless options[:verbose]

      filtered_results.each_with_index { |result, i|
        io.puts "\n%3d) %s" % [i+1, result]
      }
      io.puts
      io
    end

    def to_s # :nodoc:
      aggregated_results(StringIO.new(''.b)).string
    end

    def summary # :nodoc:
      extra = ""

      extra = "\n\nYou have skipped tests. Run with --verbose for details." if
        results.any?(&:skipped?) unless options[:verbose] or ENV["MT_NO_SKIP_MSG"]

      "%d runs, %d assertions, %d failures, %d errors, %d skips%s" %
        [count, assertions, failures, errors, skips, extra]
    end
  end

  ##
  # Dispatch to multiple reporters as one.

  class CompositeReporter < AbstractReporter
    ##
    # The list of reporters to dispatch to.

    attr_accessor :reporters

    def initialize *reporters # :nodoc:
      super()
      self.reporters = reporters
    end

    def io # :nodoc:
      reporters.first.io
    end

    ##
    # Add another reporter to the mix.

    def << reporter
      self.reporters << reporter
    end

    def passed? # :nodoc:
      self.reporters.all?(&:passed?)
    end

    def start # :nodoc:
      self.reporters.each(&:start)
    end

    def prerecord klass, name # :nodoc:
      self.reporters.each do |reporter|
        reporter.prerecord klass, name
      end
    end

    def record result # :nodoc:
      self.reporters.each do |reporter|
        reporter.record result
      end
    end

    def report # :nodoc:
      self.reporters.each(&:report)
    end
  end
end
