# This script pulls translation files from Transifex and ensures they are in the format we need.
# You need the Transifex client installed.
# http://docs.transifex.com/developer/client/setup
#
# Don't use this script to create pull requests. Do translations in Transifex.
# The Discourse team will pull them in.

require 'yaml'
require 'open3'

if `which tx`.strip.empty?
  puts ''
  puts 'The Transifex client needs to be installed to use this script.'
  puts 'Instructions are here: http://docs.transifex.com/client/setup/'
  puts ''
  puts 'On Mac:'
  puts ''
  puts '  sudo easy_install pip'
  puts '  sudo pip install transifex-client'
  exit 1
end

if ARGV.include?('force')
  puts 'Usage:   ruby pull_translations.rb [languages]'
  puts 'Example: ruby pull_translations.rb de it'
  exit 1
end

def get_languages
  if ARGV.empty?
    Dir[File.expand_path('../../config/locales/client.*.yml', __FILE__)].map { |x| x.split('.')[-2] }
  else
    ARGV
  end
end

languages = get_languages.reject { |x| x == 'en' }

puts 'Pulling new translations...'

command = "tx pull --mode=developer --force --language=#{languages.join(',')}"

Open3.popen2e(command) do |_, stdout_err, _|
  while (line = stdout_err.gets)
    puts line
  end
end

unless $?.success?
  puts 'Something failed. Check the output above.'
  exit $?.exitstatus
end

puts 'Fixing ymls...'

YML_FILE_COMMENTS = <<-END
# encoding: utf-8
#
# Never edit this file. It will be overwritten when translations are pulled from Transifex.
#
# To work with us on translations, join this project:
# https://www.transifex.com/projects/p/discourse-org/
END

YML_DIRECTORIES   = %w{config/locales plugins/poll/config/locales vendor/gems/discourse_imgur/lib/discourse_imgur/locale}
YML_FILE_PREFIXES = %w{server client}

def yml_path(dir, prefix, language)
  path = "../../#{dir}/#{prefix}.#{language}.yml"
  path = File.expand_path(path, __FILE__)
  File.exists?(path) ? path : nil
end

def write_yml(path, yml, language)
  yml_str = { language => yml }.to_yaml(line_width: -1).sub("---", YML_FILE_COMMENTS)
  File.write(path, yml_str)
end

PLURALIZATION_KEYS = %w{zero one two few many other}

# this method will deep_merge h2 into h1 but
#   - will not create new keys not already in h1
#   - except for "pluralization keys" (english only needs 'one' and 'other' but other languages might need more)
def deep_localize!(h1, h2)
  PLURALIZATION_KEYS.each { |k| h1[k] = h2[k] if h2.has_key?(k) }
  h1.each { |k, _| h1[k] = h1[k].is_a?(Hash) ? deep_localize!(h1[k], h2[k]) : h2[k] if h2.has_key?(k) }
end

YML_DIRECTORIES.each do |dir|
  YML_FILE_PREFIXES.each do |prefix|
    english_path = yml_path(dir, prefix, "en")

    languages.each do |language|
      if path = yml_path(dir, prefix, language)
        _, english_yml   = YAML.load_file(english_path).first
        _, localized_yml = YAML.load_file(path).first
        fixed_yml     = deep_localize!(english_yml, localized_yml)
        write_yml(path, fixed_yml, language)
      end
    end
  end
end

puts 'Done!'
