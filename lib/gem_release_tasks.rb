require "gem_release_tasks/version"
require 'rake'

module GemReleaseTasks
  V = /(?<before>\s*VERSION\s*=\s*")(?<major>\d+)\.(?<minor>\d+)\.(?<point>\d+)(?:\.(?<pre>\w+))?(?<after>".*)/

  def change_version
    raise "Must run GemReleaseTasks.setup(LibModule, 'path/to/version.rb') first" unless NAMESPACE
    f = File.read(NAMESPACE::VERSION_FILE)
    lines = f.each_line.map do |line|
      match = V.match line
      if match
        yield line, match[:before], match[:major], match[:minor], match[:point], match[:pre], match[:after]
      else
        line
      end
    end
    File.open(file, 'w') do |f|
      f.puts lines.join
    end
    NAMESPACE.send :remove_const, :VERSION
    load NAMESPACE::VERSION_FILE
  end

  def self.setup(namespace, version_file)
    raise "namespace must be a module" unless namespace.is_a? Module
    raise "namespace does not have a current version" unless namespace::VERSION
    raise "#{ version_file } file does not exist" unless File.exist? version_file
    raise "You may not set up GemReleaseTasks multiple times" if defined? NAMESPACE
    self.const_set :NAMESPACE, namespace
    namespace.const_set :VERSION_FILE, version_file
  end
end

task :set_release_version do
  change_version do |line, before, major, minor, point, pre, after|
    if pre
      "#{before}#{major}.#{minor}.#{point}#{after}\n"
    else
      "#{before}#{major}.#{minor}.#{point.next}#{after}\n"
    end
  end
end

task :set_development_version do
  change_version do |line, before, major, minor, point, pre, after|
    if pre
      line
    else
      "#{before}#{major}.#{minor}.#{point.next}.pre#{after}\n"
    end
  end
end

task :is_clean do
  sh "git status | grep 'working directory clean'"
end

task :is_on_master do
  sh "git status | grep 'On branch master'"
end

task :is_on_origin_master do
  sh "git log --pretty='%d' -n 1 | grep 'origin/master'"
end

task :is_up_to_date do
  sh "git pull | grep 'Already up-to-date.'"
end

task :is_release_version do
  load GemReleaseTasks::VERSION_FILE
  unless GemReleaseTasks::NAMESPACE::VERSION =~ /^\d+\.\d+\.\d+$/
    fail "Not on a release version: #{ GemReleaseTasks::NAMESPACE::VERSION }"
  end
end

task :prepare_release_push => [:is_clean, :is_on_master, :is_up_to_date, :set_release_version]

task :_only_push_release do
  load GemReleaseTasks::VERSION_FILE
  skip_ci = '[skip ci] ' if ENV['TRAVIS_SECURE_ENV_VARS']
  sh "git add #{GemReleaseTasks::VERSION_FILE} && git commit -m '#{skip_ci}Version #{ GemReleaseTasks::NAMESPACE::VERSION }' && git push"
end

task :only_push_release => [:prepare_release_push, :_only_push_release]

task :next_dev_cycle => [:is_clean, :set_development_version] do
  load GemReleaseTasks::VERSION_FILE
  sh "git add #{GemReleaseTasks::VERSION_FILE} && git commit -m '[skip ci] New development cycle with version #{ GemReleaseTasks::NAMESPACE::VERSION }'"
end

task :push_release => [:only_push_release, :next_dev_cycle]

task :release => [:is_clean, :is_on_origin_master, :is_release_version]
