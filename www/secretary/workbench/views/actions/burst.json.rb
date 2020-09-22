#
# burst a document into separate pages
#

message = Mailbox.find(@message)

attachments = []

begin
  source = message.find(@selected).as_pdf

  Dir.mktmpdir do |dir|
    Kernel.system 'pdfseparate', source.path, "#{dir}/page_%d.pdf"

    pages = Dir["#{dir}/*.pdf"].map {|name| name.untaint}
      sort_by {|name| name[/d+/].to_i}

    format = @selected.sub(/\.\w+$/, '') +
      "-%0#{pages.length.to_s.length}d.pdf"

    pages.each_with_index do |page, index|
      attachments << {
        name: format % (index+1),
        content: File.binread(page), # must use binary read
        mime: 'application/pdf'
      } if File.size? page # skip empty output files
    end
  end

  # Don't replace if no output was produced
  message.replace_attachment @selected, attachments unless attachments.empty?
rescue
  Wunderbar.error "Cannot process #{@selected}"
  raise
ensure
  source.unlink if source
end

{
  attachments: message.attachments,
  selected: (attachments.empty? ? nil : attachments.first[:name])
}
