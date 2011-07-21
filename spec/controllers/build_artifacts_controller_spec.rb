require 'spec_helper'

describe BuildArtifactsController do
  describe "#create" do
    let(:project) { projects(:big_rails_app) }
    let(:build) { project.builds.create!(:state => :partitioning, :ref => "abcdef", :queue => :ci) }
    let(:build_part) { build.build_parts.create!(:paths => ["a"], :kind => "test") }
    let(:build_attempt) { build_part.build_attempts.create!(:state => :failed) }
    let(:log_file) { File.open(FIXTURE_PATH.join("build_artifact.log")) }

    it "should create a build artifact for the build attempt" do
      log_contents = log_file.read
      log_contents.should_not be_empty

      expect {
        post :create, :build_attempt_id => build_attempt.to_param, :build_artifact => {:log_file => log_file}, :format => :xml
      }.to change{build_attempt.build_artifacts.count}.by(1)

      artifact = assigns(:build_artifact)
      artifact.log_file.read.should == log_contents
    end

    it "should return the correct location" do
      post :create, :build_attempt_id => build_attempt.to_param, :build_artifact => {:log_file => log_file}, :format => :xml
      response.should be_success
      response.location.should == assigns(:build_artifact).log_file.url
    end
  end
end
