# frozen_string_literal: true

namespace :tailwindcss do
  desc "Write resolved gem @source paths for the dummy Tailwind build"
  task inject_gem_sources: :environment do
    output = Rails.root.join("app/assets/tailwind/gem_sources.css")
    FileUtils.mkdir_p(output.dirname)
    File.write(output, Dummy::TailwindGemSources.css)
  end
end

if Rake::Task.task_defined?("tailwindcss:build")
  Rake::Task["tailwindcss:build"].enhance(["tailwindcss:inject_gem_sources"])
end

if Rake::Task.task_defined?("tailwindcss:watch")
  Rake::Task["tailwindcss:watch"].enhance(["tailwindcss:inject_gem_sources"])
end
