require "xn_gem_release_tasks/version"
require 'rake'

module Bundler
  class GemHelper
    def perform_git_push(options = '')
      cmd = "git push origin master:master #{options}"
      out, code = sh_with_code(cmd)
      raise "Couldn't git push. `#{cmd}' failed with the following output:\n\n#{out}\n" unless code == 0
    end

    def version
      XNGemReleaseTasks::NAMESPACE::VERSION
    end
  end
end


module XNGemReleaseTasks
  V = /(?<before>\s*\bVERSION\s*=\s*")(?<major>\d+)\.(?<minor>\d+)\.(?<point>\d+)(?:\.(?<pre>\w+))?(?<after>".*)/

  def self.ensure_setup
    raise "Must run XNGemReleaseTasks.setup(LibModule, 'path/to/version.rb') first" unless NAMESPACE
  end

  require 'rspec/core/rake_task'

  RSpec::Core::RakeTask.new(:spec) do |spec|
    if File.exist?('bin/rspec') && File.directory?('spec')
      spec.rspec_path = 'bin/rspec'
      spec.pattern = FileList['spec/**/*_spec.rb']
    end
  end

  def self.change_version
    ensure_setup
    f = File.read(NAMESPACE::VERSION_FILE)
    lines = f.each_line.map do |line|
      match = V.match line
      if match
        yield line, match[:before], match[:major], match[:minor], match[:point], match[:pre], match[:after]
      else
        line
      end
    end
    File.open(NAMESPACE::VERSION_FILE, 'w') do |f|
      f.puts lines.join
    end
  end

  def self.reload_version
    ensure_setup
    NAMESPACE.send :remove_const, :VERSION
    load NAMESPACE::VERSION_FILE
    NAMESPACE::VERSION
  end

  def self.setup(namespace, version_file)
    raise "namespace must be a module" unless namespace.is_a? Module
    raise "namespace does not have a current version" unless namespace::VERSION
    raise "#{ version_file } file does not exist" unless File.exist? version_file
    raise "You may not set up XNGemReleaseTasks multiple times" if defined? NAMESPACE
    self.const_set :NAMESPACE, namespace
    namespace.const_set :VERSION_FILE, version_file
  end
end

task :validate_gemspec do
  gemspec = eval(File.read(Dir['*.gemspec'].first))
  gemspec.validate
end

def command(task_name, name, &block)
  s = `which #{name}`
  if s == ""
    task(task_name, &block)
  else
    task task_name do
      # noop
    end
  end
end

desc "Ensures we are on a relesae version, and increments if we already are."
task :increment_release_version do
  XNGemReleaseTasks.change_version do |line, before, major, minor, point, pre, after|
    if pre
      "#{before}#{major}.#{minor}.#{point}#{after}\n"
    else
      "#{before}#{major}.#{minor}.#{point.next}#{after}\n"
    end
  end
end

desc "Ensures we are on a release version, but does not increment version number"
task :set_release_version do
  XNGemReleaseTasks.change_version do |line, before, major, minor, point, pre, after|
    "#{before}#{major}.#{minor}.#{point}#{after}\n"
  end
end

desc "Increments a release version number and adds .pre. Does not increment a version that is already .pre."
task :set_development_version do
  XNGemReleaseTasks.change_version do |line, before, major, minor, point, pre, after|
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
  if ENV['TRAVIS_BRANCH'] == 'master'
    true
  else
    unless ENV['IGNORE_BRANCH'] == 'true'
      sh "git status | grep 'On branch master'"
    end
  end
end

task :is_on_origin_master do
  if ENV['TRAVIS_BRANCH'] == 'master'
    true
  else
    unless ENV['IGNORE_BRANCH'] == 'true'
      result = `git log HEAD...origin/master | grep . || echo ok`
      fail "Not on origin/master" unless result.chomp == 'ok'
    end
  end
end

task :is_up_to_date do
  sh "git pull | grep 'Already up-to-date.'"
end

task :is_release_version do
  unless XNGemReleaseTasks.reload_version =~ /^\d+\.\d+\.\d+$/
    fail "Not on a release version: #{ XNGemReleaseTasks::NAMESPACE::VERSION }"
  end
end

task :prepare_release_push => [:is_clean, :is_on_master, :is_up_to_date, :set_release_version]

task :_only_push_release do
  XNGemReleaseTasks.reload_version
  if `git status | grep 'working directory clean'` == ''
    skip_ci = '[skip ci] ' if ENV['TRAVIS_SECURE_ENV_VARS']
    if sh "git add #{XNGemReleaseTasks::NAMESPACE::VERSION_FILE} && git commit -m '#{skip_ci}Version #{ XNGemReleaseTasks::NAMESPACE::VERSION }'"
      sh "git push"
    end
  end
end

task :only_push_release => [:prepare_release_push, :_only_push_release]

task :next_dev_cycle => [:is_clean, :set_development_version] do
  XNGemReleaseTasks.reload_version
  sh "git add #{XNGemReleaseTasks::NAMESPACE::VERSION_FILE} && git commit -m '[skip ci] New development cycle with version #{ XNGemReleaseTasks::NAMESPACE::VERSION }' && git push"
end

desc "Configure environment"
task :env do
  path = `echo $PATH`
  home = `echo $HOME`
  unless path.include? "#{home}/bin"
    puts "Configuring path..."
    `mkdir -p $HOME/bin`
    if File.exist? "#{home}/.zshrc"
      profile = "#{home}/.zshrc"
    else
      profile = "#{home}/.bashrc"
    end
    `echo 'export PATH="$PATH:$HOME/bin"' >> #{profile} && source #{profile}`
  end
end

desc "Install tools to interact with s3"
command(:install_aws_cli, '$HOME/bin/aws') do
  Rake::Task['env'].invoke
  puts "Installing AWS CLI tools..."
  `curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"`
  `unzip -o awscli-bundle.zip`
  `./awscli-bundle/install -i $HOME/bin/aws`
  `rm -rf awscli-bundle awscli-bundle.zip`
  `aws help`
end

desc "Install Leiningen, the clojure build tool"
command(:install_lein, '$HOME/bin/lein') do
  if File.exist? 'project.clj'
    Rake::Task['env'].invoke
    puts "Installing Leiningen..."
    `curl "https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein" -o "$HOME/bin/lein"`
    `chmod a+x $HOME/bin/lein`
    `lein`
  end
end

desc "Run Leiningen tests"
task :lein_test => [:install_lein] do
  if File.exist? 'project.clj'
    puts "Running Leiningen tests..."
    `lein test`
  else
    puts "Not a Clojure project"
  end
end

desc "Check that AWS access is configured"
task :check_aws_credentials => [:install_aws_cli] do
  gemspec = eval(File.read(Dir['*.gemspec'].first))
  check = `aws s3 ls s3://#{gemspec.name} 2>&1`
  puts check
  if check.to_s.include?("credentials")
      fail "Credentials missing. Run `aws configure` to add them or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
  end
end

desc "Check s3 to see if the gem we're building already exists"
task :validate_unique_gem => [:install_aws_cli,:check_aws_credentials] do
  gemspec = eval(File.read(Dir['*.gemspec'].first))
  unless gemspec.version.to_s.include? "pre"
    result = `aws s3 ls s3://#{gemspec.name}/gems/#{gemspec.name}-#{gemspec.version}-java.gem`
    if result.to_s.include?("#{gemspec.name}-#{gemspec.version}-java.gem")
       fail "Non-pre gem already exists on s3, only pre gems can be overwritten"
    end
  end
end

task :validate_major_push do
  gemspec = eval(File.read(Dir['*.gemspec'].first))
  unless gemspec.version.to_s.include? "pre"
    Rake::Task['is_clean'].invoke
    Rake::Task['is_on_master'].invoke
    Rake::Task['is_up_to_date'].invoke
  end
end

desc "Build gem and push to s3"
task :up => [:install_aws_cli, :validate_unique_gem, :validate_gemspec, :validate_major_push, :lein_test, :build, :spec] do
  gemspec = eval(File.read(Dir['*.gemspec'].first))
  if defined?(gemspec.platform) && gemspec.platform != ''
    gem = "#{gemspec.name}-#{gemspec.version}-#{gemspec.platform}.gem"
  else
    gem = "#{gemspec.name}-#{gemspec.version}.gem"
  end
  puts "Gem required, checking for presence..."
  `test -f #{gem}`
  puts "Pulling s3 repo and updating contents..."
  `mkdir -p repo/gems`
  `aws s3 sync s3://#{gemspec.name} repo`
  `cp pkg/#{gem} repo/gems/`
  puts "Rebuilding gem index..."
  `gem generate_index -d repo`
  puts "Pushing to s3 bucket #{gemspec.name}..."
  `aws s3 sync repo s3://#{gemspec.name}`
end

desc "Pull the repo, rebuild and push to s3"
task :repo_rebuild => [:check_aws_credentials] do
  gemspec = eval(File.read(Dir['*.gemspec'].first))
  puts "Pulling s3 repo and updating contents..."
  `mkdir -p repo/gems`
  `aws s3 sync s3://#{gemspec.name} repo`
  puts "Rebuilding gem index..."
  `gem generate_index -d repo`
  puts "Pushing to s3 bucket #{gemspec.name}..."
  `aws s3 sync repo s3://#{gemspec.name}`
end

desc "Release a new version locally rather than after a successful Travis build"
task :local_release => [:only_push_release, :release, :next_dev_cycle]

desc "Push a release candidate to Travis CI to release if it builds successfully"
task :push_release => [:only_push_release, :next_dev_cycle]

task :release => [:is_clean, :is_on_origin_master, :is_release_version]
