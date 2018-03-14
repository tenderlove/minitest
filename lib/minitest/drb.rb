# frozen_string_literal: true

require "drb"

module Minitest
  module DRb
    class Server
      include ::DRb::DRbUndumped

      def initialize finish_queue
        @work_queue = Queue.new
        @finish_queue = finish_queue
      end

      def record(reporter, result)
        reporter.synchronize do
          reporter.record(result)
        end
      end

      # Server pushes work on the queue here
      def << work
        @work_queue << work
      end

      # Client pops work off the queue here
      def pop
        @work_queue.pop
      end

      # Clients call this when they are done working
      def finish
        @finish_queue << Object.new
      end

      class Executor
        def initialize client_count, uri
          @client_count = client_count
          @finish_queue = Queue.new
          @queue      = Server.new @finish_queue
          @pool       = []

          @url = ::DRb.start_service(uri, @queue).uri
          @work_finished = nil
        end

        def start
          @work_finished = Thread.new do
            # Read from the finish_queue, client_count times. Then we know
            # all clients have finished their work
            @client_count.times { @finish_queue.pop }
          end
        end

        def << work
          @queue << work
        end

        def shutdown
          # Shutdown was called which means all work has been added to the
          # work queue.  Push `client_count` poison pills on the work queue
          # so that each client knows there is no more work to do.
          @client_count.times { @queue << nil }

          # Wait until all clients have finished their work and call `finish`
          # on the server
          @work_finished.join
        end
      end
    end

    module Client
      class Executor
        def initialize url
          ::DRb.stop_service
          @url             = url
          @queue           = nil
          @reporter        = nil
          @server_reporter = nil
        end

        def start
          @queue = ::DRbObject.new_with_uri(@url)
        end

        def << work
          @reporter = work.last
          # Clients are going to load all test cases, and they will still try
          # to queue up all their work, but we don't want the clients queued
          # up work, we want the server's queued up work. So we'll just do
          # nothing when someone tries to queue work in a client
        end

        def shutdown
          # Loop, running tests until we find a `nil` in the work queue
          while job = @queue.pop
            klass               = job[0]
            method              = job[1]
            @server_reporter ||=  job[2]
            result   = Minitest.run_one_method(klass, method)

            # Report the result locally
            @reporter.record result

            # Report the result back to the server
            @queue.record @server_reporter, result
          end

          # After we've finished all our work, let the server know we're done
          @queue.finish
        end
      end
    end
  end
end
