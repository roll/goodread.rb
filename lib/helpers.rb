require 'yaml'
require 'emoji'
require 'colorize'
$state = {'last_message_type' => nil}


# Module API

def read_config()
  config = {'documents' => ['README.md']}
  if File.file?('goodread.yml')
    config = YAML.load(File.read('goodread.yml'))
    for document, index in config['documents'].each_with_index
      if document.is_a?(Hash)
        if !document.include?('main')
          raise Exception.new('Document requires "main" property')
        end
      end
      if document.is_a?(String)
        config['documents'][index] = {'main' => document}
      end
    end
  end
  return config
end


def run_codeblock(codeblock, scope)
  lines = []
  for line in codeblock.strip().split("\n")
    if line.include?(' # ')
      left, right = line.split(' # ')
      left = left.strip()
      right = right.strip()
      if left && right
        message = "#{left} != #{right}"
        line = "raise '#{message}' unless #{left} == #{right}"
      end
    end
    lines.push(line)
  end
  exception_line = 1000 # infiinity
  exception = nil
  begin
    eval(lines.join("\n"), scope)
  rescue Exception => exc
    exception = exc
    exception_line = 1
  end
  return [exception, exception_line]
end


def print_message(message, type, level: nil, exception: nil, passed: nil, failed: nil, skipped: nil)
  text = ''
  if type == 'blank'
    return puts('')
  elsif type == 'separator'
    text = Emoji.find_by_alias('heavy_minus_sign').raw * 3
  elsif type == 'heading'
    text = " #{'#' * (level || 1)}" + message.bold
  elsif type == 'success'
    text = " #{Emoji.find_by_alias('heavy_check_mark').raw}  ".green + message
  elsif type == 'failure'
    text = " #{Emoji.find_by_alias('x').raw}  ".red + message + "\n"
    text += "Exception: #{exception}".red.bold
  elsif type == 'scope'
    text += "---\n\n"
    text += "Scope (current execution scope):\n"
    text += "#{message}\n"
    text += "\n---\n"
  elsif type == 'skipped'
    text = " #{Emoji.find_by_alias('heavy_minus_sign').raw}  ".yellow + message
  elsif type == 'summary'
    color = :green
    text = (' ' + Emoji.find_by_alias('heavy_check_mark').raw + ' ').green.bold
    if (failed + skipped) > 0
      color = :red
      text = ("\n " + Emoji.find_by_alias('x').raw + ' ').red.bold
    end
    text += "#{message}: #{passed}/#{passed + failed + skipped}".colorize(color).bold
  end
  if ['success', 'failure', 'skipped'].include?(type)
    type = 'test'
  end
  if text
    if $state['last_message_type'] != type
      text = "\n" + text
    end
    puts(text)
    $state['last_message_type'] = type
  end
end
