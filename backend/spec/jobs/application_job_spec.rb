require "rails_helper"

RSpec.describe ApplicationJob, type: :job do
  # Create a concrete subclass to test the private helpers
  let(:job_class) do
    Class.new(ApplicationJob) do
      self.queue_adapter = :test

      def perform(items, concurrency:, &block)
        run_concurrently(items, concurrency: concurrency, &block)
      end

      # Expose for testing
      public :safe_concurrency, :run_concurrently
    end
  end

  let(:job) { job_class.new }

  describe "#safe_concurrency" do
    it "returns desired when it is the smallest" do
      expect(job.safe_concurrency(1, 100)).to eq(1)
    end

    it "returns work_size when it is smaller than desired" do
      expect(job.safe_concurrency(100, 2)).to eq(2)
    end

    it "caps at pool_size - 1" do
      pool_size = ActiveRecord::Base.connection_pool.size
      available = pool_size - 1
      expect(job.safe_concurrency(1000, 1000)).to eq(available)
    end

    it "returns at least 1 even with tiny pool" do
      allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(1)
      expect(job.safe_concurrency(10, 10)).to eq(1)
    end
  end

  describe "#run_concurrently" do
    it "returns empty array for empty items" do
      results = job.run_concurrently([], concurrency: 2) { |_| "x" }
      expect(results).to eq([])
    end

    it "collects non-nil results from each block" do
      items = [ 1, 2, 3, 4 ]
      results = job.run_concurrently(items, concurrency: 2) { |n| n * 10 }
      expect(results.sort).to eq([ 10, 20, 30, 40 ])
    end

    it "excludes nil results" do
      items = [ 1, 2, 3 ]
      results = job.run_concurrently(items, concurrency: 2) { |n| n.odd? ? n : nil }
      expect(results.sort).to eq([ 1, 3 ])
    end

    it "respects concurrency limit" do
      mutex = Mutex.new
      max_concurrent = 0
      current = 0

      items = (1..10).to_a
      job.run_concurrently(items, concurrency: 3) do |_n|
        mutex.synchronize do
          current += 1
          max_concurrent = current if current > max_concurrent
        end
        sleep(0.01)
        mutex.synchronize { current -= 1 }
        nil
      end

      expect(max_concurrent).to be <= 3
    end
  end
end
