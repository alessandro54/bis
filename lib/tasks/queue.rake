namespace :queue do
  desc "Delete all finished SolidQueue jobs"
  task clear_finished: :environment do
    count = SolidQueue::Job.where.not(finished_at: nil).count
    SolidQueue::Job.where.not(finished_at: nil).delete_all
    puts "Deleted #{count} finished jobs."
  end
end
