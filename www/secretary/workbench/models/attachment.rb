require 'open3'
require_relative 'safetemp'

class Attachment
  IMAGE_TYPES = %w(.gif, .jpg, .jpeg, .png)
  attr_reader :headers

  def initialize(message, headers, part)
    @message = message
    @headers = headers
    @part = part
  end

  def name
    headers[:name] || @part.filename
  end

  def content_type
    type = headers[:mime] || @part.content_type

    if type == 'application/octet-stream' or type == 'text/plain'
      type = 'text/plain' if name.end_with? '.sig'
      type = 'text/plain' if name.end_with? '.asc'
      type = 'application/pdf' if name.end_with? '.pdf'
      type = 'image/gif' if name.end_with? '.gif'
      type = 'image/jpeg' if name.end_with? '.jpg'
      type = 'image/jpeg' if name.end_with? '.jpeg'
      type = 'image/png' if name.end_with? '.png'
    end

    type = "image/#{$1}" if type =~ /^application\/(jpeg|gif|png)$/

    type
  end

  def body
    headers[:content] || @part.body
  end

  def safe_name
    name = self.name.dup
    name.gsub! /^\W/, ''
    name.gsub! /[^\w.]/, '_'
    name.untaint
  end

  def as_file
    file = SafeTempFile.new([safe_name, '.pdf'])
    file.write(body)
    file.rewind
    file
  end

  def as_pdf
    ext = File.extname(name).downcase
    ext = '.pdf' if content_type.end_with? '/pdf'
    ext.untaint if ext =~ /^\.\w+$/

    file = SafeTempFile.new([safe_name, ext])
    file.write(body)
    file.rewind

    return file if ext == '.pdf'

    if IMAGE_TYPES.include? ext or content_type.start_with? 'image/'
      pdf = SafeTempFile.new([safe_name, '.pdf'])
      img2pdf = File.expand_path('../img2pdf', __dir__.untaint).untaint
      stdout, stderr, status = Open3.capture3 img2pdf, '--output', pdf.path,
        file.path

      # img2pdf will refuse if there is an alpha channel.  If that happens
      # use imagemagick to remove the alpha channel and try again.
      unless status.exitstatus == 0
        if stderr.include? 'remove the alpha channel'
          tmppng = SafeTempFile.new([safe_name, '.png'])
          system 'convert', file.path, '-background', 'white', '-alpha',
            'remove', '-alpha', 'off', tmppng.path

          if File.size? tmppng.path
            stdout, stderr, status = Open3.capture3 img2pdf, '--output',
              pdf.path, tmppng.path
          end

          tmppng.unlink
        end
      end

      file.unlink

      unless File.size? pdf.path
        STDERR.print stderr unless stderr.empty?
        raise "Failed to convert #{self.name} to PDF"
      end

      return pdf
    end

    return file
  end

  # write a file out to svn
  def write_svn(repos, file, path=nil)
    filename = File.join(repos, file)
    filename = File.join(filename, path || safe_name) if Dir.exist? filename

    raise Errno::EEXIST.new(file) if File.exist? filename
    File.write filename, body, encoding: Encoding::BINARY

    system 'svn', 'add', filename
    system 'svn', 'propset', 'svn:mime-type', content_type.untaint, filename

    filename
  end
end
