class LogFileUploader < CarrierWave::Uploader::Base
  storage :file

  def store_dir
    build_attempt_id = model.build_attempt_id
    build_part_id = model.build_attempt.build_part_id
    build_id = model.build_attempt.build_part.build_id
    project_param = model.build_attempt.build_part.project.to_param
    Rails.root.join("public", "log_files", project_param, "build_#{build_id}", "part_#{build_part_id}", "attempt_#{build_attempt_id}")
  end

  def cache_dir
    Rails.root.join('tmp', 'uploads')
  end
end
