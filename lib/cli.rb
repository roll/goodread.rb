require 'json'
require 'yaml'
require 'emoji'
require 'colorize'


# Helpers

def parse_specs(path)

  # Paths
  paths = []
  if !path
    paths =  Dir.glob('package.*')
    if paths.empty?
      path = 'packspec'
    end
  end
  if File.file?(path)
    paths = [path]
  elsif File.directory?(path)
    for path in Dir.glob("#{path}/*.*")
      paths.push(path)
    end
  end

  # Specs
  specs = []
  for path in paths
    spec = parse_spec(path)
    if spec
      specs.push(spec)
    end
  end

  return specs

end


def parse_spec(path)

  # Documents
  documents = []
  if !path.end_with?('.yml')
    return nil
  end
  contents = File.read(path)
  YAML.load_stream(contents) do |document|
    documents.push(document)
  end

  # Package
  feature = parse_feature(documents[0][0])
  if feature['skip']
    return nil
  end
  package = feature['comment']

  # Features
  skip = false
  features = []
  for feature in documents[0]
    feature = parse_feature(feature)
    features.push(feature)
    if feature['comment']
      skip = feature['skip']
    end
    feature['skip'] = skip || feature['skip']
  end

  # Scope
  scope = {}
  scope['$import'] = BuiltinFunctions.new().public_method(:builtin_import)
  if documents.length > 1 && documents[1]['rb']
    eval(documents[1]['rb'])
    hook_scope = Functions.new()
    for name in hook_scope.public_methods
      # TODO: filter ruby builtin methods
      scope["$#{name}"] = hook_scope.public_method(name)
    end
  end

  # Stats
  stats = {'features' => 0, 'comments' => 0, 'skipped' => 0, 'tests' => 0}
  for feature in features
    stats['features'] += 1
    if feature['comment']
      stats['comments'] += 1
    else
      stats['tests'] += 1
      if feature['skip']
        stats['skipped'] += 1
      end
    end
  end

  return {
    'package' => package,
    'features' => features,
    'scope' => scope,
    'stats' => stats,
  }

end


def parse_feature(feature)

  # General
  if feature.is_a?(String)
    match = /^(?:\((.*)\))?(\w.*)$/.match(feature)
    skip, comment = match[1], match[2]
    if !!skip
      skip = !skip.split(':').include?('rb')
    end
    return {'assign' => nil, 'comment' => comment, 'skip' => skip}
  end
  left, right = Array(feature.each_pair)[0]

  # Left side
  call = false
  match = /^(?:\((.*)\))?(?:([^=]*)=)?([^=].*)?$/.match(left)
  skip, assign, property = match[1], match[2], match[3]
  if !!skip
    skip = !skip.split(':').include?('rb')
  end
  if !assign && !property
    raise Exception.new('Non-valid feature')
  end
  if !!property
    call = true
    if property.end_with?('==')
      property = property[0..-3]
      call = false
    end
  end

  # Right side
  args = []
  kwargs = {}
  result = right
  if !!call
    result = nil
    for item in right
      if item.is_a?(Hash) && item.length == 1
        item_left, item_right = Array(item.each_pair)[0]
        if item_left == '=='
          result = item_right
          next
        end
        if item_left.end_with?('=')
          kwargs[item_left[0..-2]] = item_right
          next
        end
      end
      args.push(item)
    end
  end

  # Text repr
  text = property
  if !!assign
    text = "#{assign} = #{property || JSON.generate(result)}"
  end
  if !!call
    items = []
    for item in args
      items.push(JSON.generate(item))
    end
    for name, item in kwargs.each_pair
      items.push("#{name}=#{JSON.generate(item)}")
    end
    text = "#{text}(#{items.join(', ')})"
  end
  if !!result && !assign
    text = "#{text} == #{result == 'ERROR' ? result : JSON.generate(result)}"
  end
  text = text.gsub(/{"([^{}]*?)": null}/, '\1')

  return {
    'comment' => nil,
    'skip' => skip,
    'call' => call,
    'assign' => assign,
    'property' => property,
    'args' => args,
    'kwargs' => kwargs,
    'result' => result,
    'text' => text,
  }

end


def test_specs(specs)

  # Message
  message = "\n #  Ruby\n".bold
  puts(message)

  # Test specs
  success = true
  for spec in specs
    spec_success = test_spec(spec)
    success = success && spec_success
  end

  return success

end


def test_spec(spec)

  # Message
  message = Emoji.find_by_alias('heavy_minus_sign').raw * 3 + "\n\n"
  puts(message)

  # Test spec
  passed = 0
  for feature in spec['features']
    result = test_feature(feature, spec['scope'])
    if result
      passed += 1
    end
  end
  success = (passed == spec['stats']['features'])

  # Message
  color = 'green'
  message = ("\n " + Emoji.find_by_alias('heavy_check_mark').raw + '  ').green.bold
  if !success
    color = 'red'
    message = ("\n " + Emoji.find_by_alias('x').raw + '  ').red.bold
  end
  message += "#{spec['package']}: #{passed - spec['stats']['comments'] - spec['stats']['skipped']}/#{spec['stats']['tests'] - spec['stats']['skipped']}\n".colorize(color).bold
  puts(message)

  return success

end


def test_feature(feature, scope)

  # Comment
  if !!feature['comment']
    message = "\n # #{feature['comment']}\n".bold
    puts(message)
    return true
  end

  # Skip
  if !!feature['skip']
    message = " #{Emoji.find_by_alias('heavy_minus_sign').raw}  ".yellow
    message += feature['text']
    puts(message)
    return true
  end

  # Dereference
  # TODO: deepcopy feature
  if !!feature['call']
    feature['args'] = dereference_value(feature['args'], scope)
    feature['kwargs'] = dereference_value(feature['kwargs'], scope)
  end
  feature['result'] = dereference_value(feature['result'], scope)

  # Execute
  exception = nil
  result = feature['result']
  if !!feature['property']
    begin
      property = scope
      for name in feature['property'].split('.')
        property = get_property(property, name)
      end
      if !!feature['call']
        args = feature['args'].dup
        if !feature['kwargs'].empty?
          args.push(Hash[feature['kwargs'].map{|k, v| [k.to_sym, v]}])
        end
        if property.respond_to?('new')
          result = property.new(*args)
        else
          result = property.call(*args)
        end
      else
        result = property
        if result.is_a?(Method)
          result = result.call()
        end
      end
    rescue Exception => exc
      exception = exc
      result = 'ERROR'
    end
  end

  # Assign
  if !!feature['assign']
    owner = scope
    names = feature['assign'].split('.')
    for name in names[0..-2]
      owner = get_property(owner, name)
    end
    # TODO: ensure constants are immutable
    set_property(owner, names[-1], result)
  end

  # Compare
  if feature['result'] != nil
    success = result == feature['result']
  else
    success = result != 'ERROR'
  end
  if success
    message = " #{Emoji.find_by_alias('heavy_check_mark').raw}  ".green
    message += feature['text']
    puts(message)
  else
    begin
      result_text = JSON.generate(result)
    rescue Exception
      result_text = result.to_s
    end
    message = " #{Emoji.find_by_alias('x').raw}  ".red
    message += "#{feature['text']}\n"
    if exception
      message += "Exception: #{exception}".red.bold
    else
      message += "Assertion: #{result_text} != #{JSON.generate(feature['result'])}".red.bold
    end
    puts(message)
  end

  return success

end


class BuiltinFunctions
  def builtin_import(package)
    attributes = {}
    require(package)
    for item in ObjectSpace.each_object
      if package == String(item).downcase
        begin
          scope = Kernel.const_get(item)
        rescue Exception
          next
        end
        for name in scope.constants
          attributes[String(name)] = scope.const_get(name)
        end
      end
    end
    return attributes
  end
end


def dereference_value(value, scope)
  if value.is_a?(Hash) && value.length == 1 && Array(value.each_value)[0] == nil
    result = scope
    for name in Array(value.each_key)[0].split('.')
      result = get_property(result, name)
    end
    value = result
  elsif value.is_a?(Hash)
    for key, item in value
      value[key] = dereference_value(item, scope)
    end
  elsif value.is_a?(Array)
    for item, index in value.each_with_index
      value[index] = dereference_value(item, scope)
    end
  end
  return value
end


def get_property(owner, name)
  if owner.is_a?(Method)
    owner = owner.call()
  end
  if owner.class == Hash
    return owner[name]
  elsif owner.class == Array
    return owner[name.to_i]
  end
  return owner.method(name)
end


def set_property(owner, name, value)
  if owner.class == Hash
    owner[name] = value
    return
  elsif owner.class == Array
    owner[name.to_i] = value
    return
  end
  return owner.const_set(name, value)
end


# Main program

path = ARGV[0] || nil
specs = parse_specs(path)
success = test_specs(specs)
if !success
  exit(1)
end
