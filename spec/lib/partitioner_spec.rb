require 'spec_helper'
require 'partitioner'

describe Partitioner do
  let(:build) { FactoryGirl.create(:build) }
  let(:partitioner) { Partitioner.new }

  before do
    allow(GitRepo).to receive(:load_kochiku_yml).and_return(kochiku_yml)
    allow(GitRepo).to receive(:inside_copy).and_yield()
  end

  let(:kochiku_yml) {
    [
      {
        'type' => 'rspec',
        'glob' => 'spec/**/*_spec.rb',
        'workers' => 3,
        'balance' => rspec_balance,
        'manifest' => rspec_manifest,
        'time_manifest' => rspec_time_manifest,
      },
      {
        'type' => 'cuke',
        'glob' => 'features/**/*.feature',
        'workers' => 3,
        'balance' => cuke_balance,
        'manifest' => cuke_manifest,
        'time_manifest' => cuke_time_manifest,
      }
    ]
  }

  let(:pom_xml_exists) { false }
  let(:rspec_balance) { 'alphabetically' }
  let(:rspec_manifest) { nil }
  let(:cuke_balance) { 'alphabetically' }
  let(:cuke_manifest) { nil }
  let(:rspec_time_manifest) { nil }
  let(:cuke_time_manifest) { nil }

  context "with a kochiku.yml that does not use Ruby" do
    let(:kochiku_yml) do
      {
        "targets" => [
          {
            'type' => 'other',
            'glob' => 'spec/**/*_spec.rb',
            'workers' => 1,
          }
        ]
      }
    end

    it "should not include a ruby version" do
      partitions = partitioner.partitions(build)
      expect(partitions.size).to be(1)
      expect(partitions.first["type"]).to eq("other")
      expect(partitions.first["files"]).not_to be_empty
      expect(partitions.first["options"]).not_to have_key("ruby")
    end
  end

  context "with a kochiku.yml that specifies log files" do
    let(:kochiku_yml) do
      {
        'log_file_globs' => ['glob1'],
        "targets" => [
          {
            'type' => 'other',
            'glob' => 'spec/**/*_spec.rb',
            'workers' => 1,
          },
        ]
      }
    end

    it "should include the log_file_globs" do
      partitions = partitioner.partitions(build)
      expect(partitions.first['options']['log_file_globs']).to eq(['glob1'])
    end

    context "with a kochiku.yml that specifies log files" do
      let(:kochiku_yml) do
        {
          'log_file_globs' => ['glob1'],
          "targets" => [
            {
              'type' => 'other',
              'glob' => 'spec/**/*_spec.rb',
              'workers' => 1,
              'log_file_globs' => ['glob2'],
            },
          ]
        }
      end

      it "should not include a ruby version" do
        partitions = partitioner.partitions(build)
        expect(partitions.first['options']['log_file_globs']).to eq(['glob2'])
      end
    end
  end

  context "with a ruby-based kochiku.yml" do
    let(:queue_override) { nil }
    let(:retry_count) { nil }
    let(:kochiku_yml) do
      {
        "ruby" => ["ree-1.8.7-2011.12"],
        "language" => "ruby",
        "targets" => [
          {
            'type' => 'rspec',
            'glob' => 'spec/**/*_spec.rb',
            'workers' => 3,
            'balance' => rspec_balance,
            'manifest' => rspec_manifest,
            'queue_override' => queue_override,
            'retry_count' => retry_count,
          }
        ]
      }
    end

    it "parses options from kochiku yml" do
      partitions = partitioner.partitions(build)
      expect(partitions.first["options"]["language"]).to eq("ruby")
      expect(partitions.first["options"]["ruby"]).to eq("ree-1.8.7-2011.12")
      expect(partitions.first["type"]).to eq("rspec")
      expect(partitions.first["files"]).not_to be_empty
      expect(partitions.first["queue"]).to eq("developer")
      expect(partitions.first["retry_count"]).to eq(0)
    end

    context "with a master build" do
      let(:build) { FactoryGirl.create(:main_project_build) }

      it "should use the ci queue" do
        expect(build.project).to be_main
        partitions = partitioner.partitions(build)
        expect(partitions.first["queue"]).to eq("ci")
      end
    end

    context "with a branch build" do
      it "should use the developer queue" do
        expect(build.project).to_not be_main
        partitions = partitioner.partitions(build)
        expect(partitions.first["queue"]).to eq("developer")
      end
    end

    context "with queue_override" do
      let(:queue_override) { "override" }
      it "should override the queue on the build part" do
        partitions = partitioner.partitions(build)
        expect(partitions.first["queue"]).to eq("override")
      end
    end

    context "with retry_count" do
      let(:retry_count) { 2 }
      it "should set the retry count" do
        partitions = partitioner.partitions(build)
        expect(partitions.first["retry_count"]).to eq(2)
      end
    end
  end

  context "when there is no kochiku yml" do
    let(:kochiku_yml) { nil }

    it "should return a single partiion" do
      partitions = partitioner.partitions(build)
      expect(partitions.size).to eq(1)
      expect(partitions.first["type"]).to eq("spec")
      expect(partitions.first["files"]).not_to be_empty
    end
  end

  describe '#partitions' do
    subject { partitioner.partitions(build) }

    context 'when there is not a kochiku.yml' do
      let(:kochiku_yml) { nil }
      it { should == [{"type" => "spec", "files" => ['no-manifest'], 'queue' => 'developer', 'retry_count' => 0}] }
    end

    context 'when there is a kochiku.yml' do

      before { allow(Dir).to receive(:[]).and_return(matches) }

      context 'when there are no files matching the glob' do
        let(:matches) { [] }
        it { should == [] }
      end

      context 'when there is one file matching the glob' do
        let(:matches) { %w(a) }
        it { [{ 'type' => 'rspec', 'files' => %w(a), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} }].each { |partition| should include(partition) } }
      end

      context 'when there are many files matching the glob' do
        let(:matches) { %w(a b c d) }
        it {
          [
            { 'type' => 'rspec', 'files' => %w(a b), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
            { 'type' => 'rspec', 'files' => %w(c), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
            { 'type' => 'rspec', 'files' => %w(d), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
          ].each { |partition| should include(partition) }
        }

        context 'and balance is round_robin' do
          let(:rspec_balance) { 'round_robin' }
          it {
            [
              { 'type' => 'rspec', 'files' => %w(a d), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(b), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(c), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
            ].each { |partition| should include(partition) }
          }

          context 'and a manifest file is specified' do
            before { allow(YAML).to receive(:load_file).with(rspec_manifest).and_return(%w(c b a)) }
            let(:rspec_manifest) { 'manifest.yml' }
            let(:matches) { %w(a b c d) }

            it {
              [
                { 'type' => 'rspec', 'files' => %w(c d), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
                { 'type' => 'rspec', 'files' => %w(b), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
                { 'type' => 'rspec', 'files' => %w(a), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              ].each { |partition| should include(partition) }
            }
          end

          context 'and time manifest files are specified' do
            before do allow(YAML).to receive(:load_file).with(rspec_time_manifest).and_return(
                {
                  'a.spec' => [2],
                  'b.spec' => [5, 8],
                  'c.spec' => [9, 6],
                  'd.spec' => [5, 8],
                  'deleted.spec' => [10],
                }
              )
            end

            before do allow(YAML).to receive(:load_file).with(cuke_time_manifest).and_return(
              {
                'f.feature' => [2],
                'g.feature' => [5, 8],
                'h.feature' => [6, 9],
                'i.feature' => [15, 16],
              }
            )
            end

            let(:rspec_time_manifest) { 'rspec_time_manifest.yml' }
            let(:cuke_time_manifest) { 'cuke_time_manifest.yml' }
            let(:spec_matches) { %w(a.spec b.spec c.spec d.spec e.spec) }
            let(:feature_matches) { %w(f.feature g.feature h.feature i.feature) }

            it 'should greedily partition files in the time_manifest, and round robin the remaining files' do
              allow(Dir).to receive(:[]).with("spec/**/*_spec.rb").and_return(spec_matches)
              allow(Dir).to receive(:[]).with("features/**/*.feature").and_return(feature_matches)
              [
                  {"type"=>"rspec", "files"=>["c.spec"], "queue"=>"developer", "retry_count"=>0, 'options' => {}},
                  {"type"=>"rspec", "files"=>["d.spec", "e.spec"], "queue"=>"developer", "retry_count"=>0, 'options' => {}},
                  {"type"=>"rspec", "files"=>["b.spec", "a.spec"], "queue"=>"developer", "retry_count"=>0, 'options' => {}},
                  {"type"=>"cuke", "files"=>["i.feature"], "queue"=>"developer", "retry_count"=>0, 'options' => {}},
                  {"type"=>"cuke", "files"=>["h.feature"], "queue"=>"developer", "retry_count"=>0, 'options' => {}},
                  {"type"=>"cuke", "files"=>["g.feature", "f.feature"], "queue"=>"developer", "retry_count"=>0, 'options' => {}}
              ].each { |partition| should include(partition) }
            end
          end
        end

        context 'and balance is size' do
          let(:rspec_balance) { 'size' }

          before do
            allow(File).to receive(:size).with('a').and_return(1)
            allow(File).to receive(:size).with('b').and_return(1000)
            allow(File).to receive(:size).with('c').and_return(100)
            allow(File).to receive(:size).with('d').and_return(10)
          end

          it {
            [
              { 'type' => 'rspec', 'files' => %w(b a), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(c), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(d), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
            ].each { |partition| should include(partition) }
          }
        end

        context 'and balance is size_greedy_partitioning' do
          let(:rspec_balance) { 'size_greedy_partitioning' }

          before do
            allow(File).to receive(:size).with('a').and_return(1)
            allow(File).to receive(:size).with('b').and_return(1000)
            allow(File).to receive(:size).with('c').and_return(100)
            allow(File).to receive(:size).with('d').and_return(10)
          end

          it {
            [
              { 'type' => 'rspec', 'files' => %w(b), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(c), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(d a), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
            ].each { |partition| should include(partition) }
          }
        end

        context 'and balance is size_average_partitioning' do
          let(:rspec_balance) { 'size_average_partitioning' }

          before do
            allow(File).to receive(:size).with('a').and_return(1)
            allow(File).to receive(:size).with('b').and_return(1000)
            allow(File).to receive(:size).with('c').and_return(100)
            allow(File).to receive(:size).with('d').and_return(10)
          end

          it {
            [
              { 'type' => 'rspec', 'files' => %w(a b), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(c), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(d), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
            ].each { |partition| should include(partition) }
          }
        end

        context 'and balance is isolated' do
          let(:rspec_balance) { 'isolated' }

          it {
            [
              { 'type' => 'rspec', 'files' => %w(a), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(b), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(c), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
              { 'type' => 'rspec', 'files' => %w(d), 'queue' => 'developer', 'retry_count' => 0, 'options' => {} },
            ].each { |partition| should include(partition) }
          }
        end
      end
    end
  end
end
