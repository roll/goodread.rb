require 'json'
require 'yaml'
require 'emoji'
require 'colorize'
require_relative 'document'
require_relative 'helpers'


# Main program

# Parse
paths = []
edit = false
sync = false
exit_first = false
for arg in ARGV
  if ['-e', '--edit'].include?(arg)
    edit = true
  elsif ['-s', '--sync'].include?(arg)
    sync = true
  elsif ['-x', '--exit-first'].include?(arg)
    exit_first = true
  else
    paths.push(arg)
  end
end

# Prepare
config = read_config()
documents = DocumentList.new(paths, config)

# Edit
if edit
  documents.edit()

# Sync
elsif sync
  documents.sync()

# Test
else
  success = documents.test(exit_first:exit_first)
  if not success
    exit(1)
  end
end
