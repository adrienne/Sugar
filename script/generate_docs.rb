
require 'rubygems'
require 'json'
require 'pp'

fileout  = ARGV[0] || '/Volumes/Andrew/Sites/sugarjs.com/public_html/javascripts/packages.js'

@locales_preamble = <<TEXT
  /***
   * @package Date Locales
   * @dependency date
   * @description Locale definitions French (fr), Italian (it), Spanish (es), Portuguese (pt), German (de), Russian (ru), Polish (pl), Swedish (sv), Japanese (ja), Korean (ko), Simplified Chinese (zh-CN), and Traditional Chinese (zh-TW). Locales can also be included individually. See @date_locales for more.
   *
   ***/
TEXT

fileout_html  = File.open(fileout, 'r').read if File.exists?(fileout)

@packages = {}
@default_packages = [:core,:es5,:array,:object,:date,:date_ranges,:function,:number,:regexp,:string]

def create_locale_package
  file = 'lib/date_locales.js'
  locales = `cat lib/locales/*`
  File.open(file, 'w').write(@locales_preamble + locales)
end

def get_current_version
  package = JSON.parse(File.open('package.json', 'r').read)
  @version = package['version'].sub(/\.0$/, '')
end

def cleanup
  `rm lib/date_locales.js`
end

def get_property(prop, s, multiline = false)
  if multiline
    r = Regexp.new('@'+prop.to_s+'[\s*]+\*\n?(.+?)\*\n', Regexp::MULTILINE)
    match = s.scan(r)
    match[0][0].split(/\n/) if match[0]
  else
    match = s.match(Regexp.new('@'+prop.to_s+' (.*)'))
    match[1] if match
  end
end

def get_method(s)
  raw = get_property(:method, s)
  match = raw.match(/(.+\.)?(.+)\((.+)?\)/)
  name = match[2]
  method = {}
  if !!match[1]
    method[:class_method] = true
  end
  params = []
  accepts_unlimited_params = false
  if match[3]
    p = match[3].split(/,(?!')/)
    if p.last =~ /[^'"]\.\.\./
      p.delete_at(-1)
      method[:accepts_unlimited_params] = true
    end
    params = p.to_enum(:each_with_index).map do |f,i|
      required = !!f.match(/<.+>/)
      param_name = f.match(/[<\[](.+)[>\]]/)[1]
      default = f.match(/ = (.+)/)
      css = ''
      css << 'required ' if required
      css << 'parameter'
      if default
        d = default[1]
        if d =~ /['"].*['"]/
          type = :string
          d.gsub!(/(['"])(.+)(['"])/, '\\1<span class="monospace">\\2</span>\\3')
        elsif d =~ /\d+/
          type = :number
        elsif d =~ /\/.+\//
          type = :regexp
        elsif d =~ /^null$/
          type = :null
        elsif d =~ /true|false/
          type = :boolean
        elsif d =~ /\{\}/
          type = :object
        end
        d = '<span class="' + type.to_s + ' monospace value">' + d + '</span>'
      end
      {
        :name => param_name,
        :type => type,
        :required => required,
        :default => default ? default[1] : nil
      }
    end
  else
    params = []
  end
  method[:params] = params if params.size > 0
  [name, method]
end

def get_examples(s)
  lines = get_property(:example, s, true)
  return nil if !lines
  examples = []
  func = ''
  force_result = false
  lines.each do |l|
    l.gsub!(/^[\s*]+/, '')
    l.gsub!(/\s+->.+$/, '')
    if l =~ /^\s*\+/
      force_result = true
      l.gsub!(/\+/, '')
    end
    if l =~ /function/ && l !~ /isFunction/
      func << l
    elsif l =~ /\);$/
      func << l.gsub(/\s+->.+$/, '').gsub(/\}/, '\n}')
      func.gsub!(/(['"]).+?(\1)/) do |s|
        s.gsub(/\\n/, '_NL_')
      end
      examples << { :multi_line => true, :force_result => force_result, :html => func }
      func = ''
    elsif func.length > 0
      func << '\n' + l
    elsif !l.empty?
      examples << {
        :multi_line => false,
        :force_result => force_result,
        :html => l.gsub(/\s+->.+$/, '').gsub(/\\n/, '_NL_')
      }
    end
  end
  examples.each do |ex|
    clean(ex)
  end
  examples
end

def clean(m)
  m.each do |key, value|
    if value.nil? || value == false
      m.delete(key)
    end
  end
end

def get_set(s)
  lines = get_property(:set, s, true)
  lines.map do |l|
    l.gsub!(/^[\s\*]+/, '')
    if l == ''
      nil
    else
      l
    end
  end.compact if lines
end

def get_minified_size(package)
  tmp = 'tmp/package.js'
  `cp release/#{@version}/precompiled/minified/#{package}.js #{tmp}`
  `gzip --best #{tmp}`
  size = File.size("#{tmp}.gz")
  # gzipping the packages together produces sizes
  # less than gzipping individually, so offset this
  # a bit... just eyeballin it
  size -= 190 if package != :regexp
  `rm #{tmp}.gz`
  size
end

def get_full_size(package)
  File.size("lib/#{package}.js")
end

def match_block(b, linenum, package)
  return if b.strip == ''
  if match = b.match(/@package (\w+)/)

    name = match[1]

    # package dependency
    match = b.match(/@dependency (.+)/)
    if match && match[1]
      @packages[package][:dependency] = match[1]
    end

    # package description
    match = b.match(/@description (.+)/)
    if match && match[1]
      @packages[package][:description] = match[1]
    end

    @packages[package][:modules][name.to_sym] ||= {}
    @current_module = @packages[package][:modules][name.to_sym]
  elsif match = b.match(/(\w+) module/)
    name = match[1]
    @packages[package][:modules][name.to_sym] ||= {}
    @current_module = @packages[package][:modules][name.to_sym]
  else
    name, method = get_method(b)
    # Go 5 lines up so there's a little padding (Github doesn't do this)
    method[:line] = [0, linenum - 5].max
    method[:returns] = get_property(:returns, b)
    method[:short] = get_property(:short, b)
    method[:extra] = get_property(:extra, b)
    method[:set] = get_set(b)
    method[:examples] = get_examples(b)
    method[:alias] = get_property(:alias, b)
    @current_module[name] = method
    if name == 'stripTags' || name == 'removeTags' || name == 'escapeHTML' || name == 'unescapeHTML'
      method[:escape_html] = true
    end
    if method[:alias]
      method.delete_if { |k,v| v.nil? || (v.is_a?(Array) && v.empty?) }
      method[:short] = "Alias for %#{method[:alias]}%."
    end
    clean(method)
  end
end

def extract_docs(package)
  @packages[package] ||= {
    :size => get_full_size(package),
    :minified_size => get_minified_size(package),
    :extra => !@default_packages.include?(package),
    :modules => {}
  }
  File.open("lib/#{package}.js", 'r') do |f|
    i = 0
    b = ''
    linenum = nil
    f.each_line do |line|
      if line =~ /\/\*\*\*/
        b = ''
        linenum = f.lineno
      elsif line =~ /\*\*\*/
        match_block(b, linenum, package)
        b = ''
        linenum = f.lineno
      end
      b << line
    end
  end
end

create_locale_package
get_current_version

extract_docs(:core)
extract_docs(:es5)
extract_docs(:array)
extract_docs(:object)
extract_docs(:date)
extract_docs(:date_locales)
extract_docs(:date_ranges)
extract_docs(:function)
extract_docs(:number)
extract_docs(:regexp)
extract_docs(:string)
extract_docs(:inflections)
extract_docs(:language)

cleanup
puts 'Done!'

File.open(fileout, 'w') do |f|
  f.puts "SugarPackages = #{@packages.to_json};"
end
