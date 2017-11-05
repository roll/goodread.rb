require 'net/http'
require_relative 'helpers'


# Module API

class DocumentList

  # Public

  def initialize(paths, config)
    @documents = []
    if paths.empty?
      for item in config['documents']
        paths.push(item['main'])
      end
    end
    for path in !paths.empty? ? paths : ['README.md']
      main_path = path
      edit_path = nil
      sync_path = nil
      for item in config['documents']
        if path == item['main']
          edit_path = item.fetch('edit', nil)
          sync_path = item.fetch('sync', nil)
          break
        end
      end
      document = Document.new(main_path, edit_path:edit_path, sync_path:sync_path)
      @documents.push(document)
    end
  end

  def edit()
    for document in @documents
      document.edit()
    end
  end

  def sync()
    success = true
    for document in @documents
      valid = document.test(sync:true)
      success = success && valid
      if valid
        document.sync()
      end
    end
    return success
  end

  def test(exit_first:false)
    success = true
    for document, index in @documents.each_with_index
      number = index + 1
      valid = document.test(exit_first:exit_first)
      success = success && valid
      print_message(nil, (number < @documents.length ? 'separator' : 'blank'))
    end
    return success
  end

end


class Document

  # Public

  def initialize(main_path, edit_path:nil, sync_path:nil)
    @main_path = main_path
    @edit_path = edit_path
    @sync_path = sync_path
  end

  def edit()

    # No edit path
    if !@edit_path
      return
    end

    # Check synced
    if @main_path != @edit_path
      main_contents = _load_document(@main_path)
      sync_contents = _load_document(@sync_path)
      if main_contents != sync_contents
        raise Exception.new("Document '#{@edit_path}' is out of sync")
      end
    end

    # Remote document
    if !@edit_path.start_with?('http')
      Kernel.system(['editor', @edit_path])

    # Local document
    else
      Kernel.system(['xdg-open', @edit_path])
    end

  end

  def sync()

    # No sync path
    if !@sync_path
      return
    end

    # Save remote to local
    contents = Net::HTTP.get(URI(@sync_path))
    File.write(@main_path, contents)

  end

  def test(sync:false, return_report:false, exit_first:false)

    # No test path
    path = sync ? @sync_path : @main_path
    if !path
      return true
    end

    # Test document
    contents = _load_document(path)
    elements = _parse_document(contents)
    report = _validate_document(elements, exit_first:exit_first)

    return return_report ? report : report['valid']
  end

end


# Internal

def _load_document(path)

  # Remote document
  if path.start_with?('http')
    return Net::HTTP.get(URI(path))

  # Local document
  else
    return File.read(path)
  end

end


def _parse_document(contents)
  elements = []
  codeblock = ''
  capture = false

  # Parse file lines
  for line in contents.strip().split("\n")

    # Heading
    if line.start_with?('#')
      heading = line.strip().tr('#', '')
      level = line.length - line.tr('#', '').length
      if (!elements.empty? &&
          elements[-1]['type'] == 'heading' &&
          elements[-1]['level'] == level)
        next
      end
      elements.push({
        'type' => 'heading',
        'value' => heading,
        'level' => level,
      })
    end

    # Codeblock
    if line.start_with?('```ruby')
      if line.include?('goodread')
        capture = true
      end
      codeblock = ''
      next
    end
    if line.start_with?('```')
      if capture
        elements.push({
          'type' => 'codeblock',
          'value' => codeblock,
        })
      end
      capture = false
    end
    if capture && !line.empty?
      codeblock += line + "\n"
      next
    end

  end

  return elements
end


def _validate_document(elements, exit_first:false)
  scope = binding()
  passed = 0
  failed = 0
  skipped = 0
  title = nil
  exception = nil

  # Test elements
  for element in elements

    # Heading
    if element['type'] == 'heading'
      print_message(element['value'], 'heading', level:element['level'])
      if title == nil
        title = element['value']
        print_message(nil, 'separator')
      end

    # Codeblock
    elsif element['type'] == 'codeblock'
      exception_line = 1000  # infinity
      begin
        eval(instrument_codeblock(element['value']), scope)
      rescue Exception => exc
        exception = exc
        # TODO: get a real exception line
        exception_line = 1
      end
      lines = element['value'].strip().split("\n")
      for line, index in lines.each_with_index
        line_number = index + 1
        if line_number < exception_line
          print_message(line, 'success')
          passed += 1
        elsif line_number == exception_line
          print_message(line, 'failure', exception:exception)
          if exit_first
            print_message(scope, 'scope')
            raise exception
          end
          failed += 1
        elsif line_number > exception_line
          print_message(line, 'skipped')
          skipped += 1
        end
      end
    end

  end

  # Print summary
  if title != nil
    print_message(title, 'summary', passed:passed, failed:failed, skipped:skipped)
  end

  return {
    'valid' => exception == nil,
    'passed' => passed,
    'failed' => failed,
    'skipped' => skipped,
  }
end
