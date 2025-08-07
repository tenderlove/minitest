module Minitest
  module Ractorize # :nodoc:

    ##
    # The engine used to run multiple tests in parallel.

    class Executor

      ##
      # The size of the pool of workers.

      attr_reader :size

      ##
      # Create a parallel test executor of with +size+ workers.

      def initialize size
        @size  = size
        channel = Ractor::Port.new
        @coordinator = Ractor.new(channel, size) { |channel, size|
          queue = Ractor::Port.new
          channel << queue

          # Get work from the queue
          while work = queue.receive
            # Pass work to the next Ractor that asks for work
            Ractor.receive << work
          end

          # Once we get a nil, we need to shut down the workers
          size.times { Ractor.receive << nil }
        }
        @queue = channel.receive
        @pool  = nil
      end

      ##
      # Start the executor

      def start
        @pool  = Array.new(size) {
          Ractor.new(@coordinator) { |c|
            loop do
              # tell the coordinator I want work
              c << self
              work = Ractor.receive
              break unless work
              klass, method, reporter = work
              reporter.prerecord klass, method
              result = Minitest.run_one_method klass, method
              reporter.record result
            end
          }
        }
      end

      ##
      # Add a job to the queue

      def << work
        @queue << work
      end

      ##
      # Shuts down the pool of workers by signalling them to quit and
      # waiting for them all to finish what they're currently working
      # on.

      def shutdown
        @queue << nil
        @pool.each(&:value)
      end
    end

    module Test # :nodoc:
      module ClassMethods # :nodoc:
        def run_one_method klass, method_name, reporter
          Minitest.parallel_executor << [klass, method_name, reporter]
        end

        def test_order
          :parallel
        end
      end
    end
  end
end
