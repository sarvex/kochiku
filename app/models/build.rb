class Build < ActiveRecord::Base
  belongs_to :project
  has_many :build_parts, :dependent => :destroy
  has_many :build_attempts, :through => :build_parts
  symbolize :state, :in => [:partitioning, :runnable, :running, :doomed, :failed, :succeeded, :error]
  symbolize :queue
  validates_presence_of :queue
  validates_presence_of :project_id

  after_create :enqueue_partitioning_job

  def enqueue_partitioning_job
    Resque.enqueue(BuildPartitioningJob, self.id)
  end

  def partition(parts)
    transaction do
      update_attributes!(:state => :runnable)
      parts.each { |part| build_parts.create!(:kind => part['type'], :paths => part['files']) }
    end
  end

  def update_state_from_parts!
    return if build_parts.empty?
    passed = build_parts.passed
    failed = build_parts.failed
    state =
      if (build_parts - passed).empty?
        :succeeded
      elsif (passed | failed) == build_parts
        :failed
      else
         failed.empty? ? :running : :doomed
      end
    update_attributes!(:state => state)
  end

  def started_at
    build_attempts.order('started_at asc').first.started_at
  end

  def finished_at
#    build_attempts.all.sort_by(&:finished_at).last
  end

  def succeeded?
    state == :succeeded
  end

  def promotable?
    succeeded? && queue == :master
  end

  def promote!
    BuildStrategy.new.promote_build(self)
  end
end
