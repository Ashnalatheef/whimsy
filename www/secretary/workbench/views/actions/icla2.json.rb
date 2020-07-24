#
# File an additional ICLA:
#  - [optional] move existing ICLA into a directory
#  - add files to (new) documents/iclas dirctory
#  - modify officers/iclas.txt entry
#  - respond to original email
#

# extract message
message = Mailbox.find(@message)

# find person
person = ASF::Person.find(@id)

# extract file extension
fileext = File.extname(@selected).downcase if @signature.empty?

# obtain per-user information
_personalize_email(env.user)

########################################################################
#                        move existing document                        #
########################################################################

@filename.untaint if @filename =~ /\A\w[-.\w]*\z/

if @email.strip.end_with? '@apache.org'
  _warn "Cannot redirect email to an @apache.org address: #{@email.strip}"
end

if not ASF::ICLAFiles.Dir? @filename
  # Assumes there is a single matching file
  @existing = ASF::ICLAFiles.matchStem(@filename).first
  task "svn mv #@existing #@filename/icla#{File.extname(@existing)}" do
    form do
      _input value: @existing, name: 'existing'
    end

    complete do |dir|
      # checkout empty iclas directory
      svn 'checkout', '--depth', 'empty',
        ASF::SVN.svnurl('iclas'), "#{dir}/iclas"

      # update file to be moved
      svn 'update', "#{dir}/iclas/#{@existing}"

      # create target directory
      FileUtils.mkdir "#{dir}/iclas/#{@filename}"
      svn 'add', "#{dir}/iclas/#{@filename}"

      # update file to be moved
      svn 'mv', "#{dir}/iclas/#{@existing}", 
        "#{dir}/iclas/#@filename/icla#{File.extname(@existing)}"

      # commit changes
      svn 'commit', "#{dir}/iclas", '-m', "move previous ICLA from #{@pubname}"
    end
  end
end

########################################################################
#                          file new document                           #
########################################################################

# determine what the counter is likely to be by querying the server
# Notes:
#   - ASF::SVN.list returns 
#     - a string with "\n" separators
#     - If there is an error ASF::SVN.list returns an array with nil
#       as the first entry.
#   - Converting the results to an array, extracting the first entry,
#     coorsing it to a string, and then splitting it will result in an array
#   - calling .max on an empty array returns nil.  Treat it as one as there
#     is an existing document that will be moved into this directory.
#   - If all else fails, set count to "N"
count = (Array(ASF::SVN.list((ASF::SVN.svnurl('iclas') + '/' + @filename).untaint)).
      first.to_s.split.
      map {|name| name[/.*(\d+)\./, 1] || 1}.
      map(&:to_i).max || 1) + 1 rescue 'N'

# write attachment (+ signature, if present) to the documents/iclas directory
task "svn commit documents/iclas/#@filename/iclaN#{count}#{fileext}" do
  form do
    _input value: @selected, name: 'selected'

    if @signature and not @signature.empty?
      _input value: @signature, name: 'signature'
    end
  end

  complete do |dir|
    # checkout directory
    svn 'checkout',
      ASF::SVN.svnpath!('iclas', @filename),
      File.join(dir, @filename)

    # determine numeric suffix for the new ICLA
    count = Dir[File.join(dir, @filename, '*')].
      map {|name| name[/.*(\d+)\./, 1] || 1}.map(&:to_i).max + 1

    # create/add file(s)
    files = {@selected => "icla#{count}#{fileext}"}
    files[@signature]  = "icla#{count}pdf.asc" unless @signature.to_s.empty?
    message.write_svn(dir, @filename, files)

    # Show files to be added
    svn 'status', File.join(dir, @filename)

    # commit changes
    svn 'commit', 
      *files.values.map {|name| "#{dir}/#@filename/#{@name}"},
      '-m', "additional ICLA from #{@pubname}"
  end
end

########################################################################
#                          officers/iclas.txt                          #
########################################################################

# insert line into iclas.txt
task "svn commit foundation/officers/iclas.txt" do
  icla = ASF::ICLA.find_by_id(@id) || ASF::ICLA.find_by_email(@oldemail)
  unless icla and icla.id == @id and icla.email == @oldemail
    raise ArgumentError.new("ICLA not found for #@id:#@oldemail")
  end

  # construct line to be inserted
  @iclaline ||= [
    @id,
    icla.legal_name,
    @pubname.strip,
    @email.strip,
    icla.form
  ].join(':')

  form do
    _input value: @iclaline, name: 'iclaline'
  end

  complete do |dir|
    # checkout empty officers directory
    svn 'checkout', '--depth', 'empty',
      ASF::SVN.svnurl('officers'), 
      File.join(dir, 'officers')

    # retrieve iclas.txt
    dest = File.join(dir, 'officers', 'iclas.txt')
    svn 'update', dest

    # update iclas.txt
    iclas_txt = File.read(dest)
    iclas_txt[/^#{@id}:.*:#{@oldemail}:.*/] = @iclaline
    File.write dest, ASF::ICLA.sort(iclas_txt)

    # show the changes
    svn 'diff', dest

    # commit changes
    svn 'commit', dest, '-m', "ICLA for #{@pubname}"
  end
end

########################################################################
#                      update public name in LDAP                      #
########################################################################

if person.public_name != @pubname and @id != 'notinavail'
  task "change public name in LDAP" do
    form do
      _input value: @pubname, name: 'pubname'
    end

    complete do
      ldap = ASF.init_ldap(true)

      ldap.bind("uid=#{env.user.untaint},ou=people,dc=apache,dc=org",
        env.password.untaint)

      ldap.modify person.dn, [ASF::Base.mod_replace('cn', @pubname.strip)]

      log = ["LDAP modify: #{ldap.err2string(ldap.err)} (#{ldap.err})"]
      if ldap.err == 0
        _transcript log
      else
        _backtrace log
      end

      ldap.unbind
    end
  end
end

########################################################################
#                           email submitter                            #
########################################################################

# send confirmation email
task "email #@email" do
  cc = person.all_mail.map {|email| "#{@pubname.inspect} <#{email}>"}
  cc << 'secretary@apache.org'

  # build mail from template
  mail = message.reply(
    subject: "ICLA for #{@pubname}",
    from: @from,
    to: "#{@pubname.inspect} <#{@email}>",
    cc: cc,
    body: template('icla2.erb')
  )

  # echo email
  form do
    _message mail.to_s
  end

  # deliver mail
  complete do
    mail.deliver!
  end
end

########################################################################
#                     update email address in LDAP                     #
########################################################################

if @id != 'notinavail'
  task "change email address in LDAP" do
    form do
      _input value: @email, name: 'email'
    end

    complete do
      ldap = ASF.init_ldap(true)

      ldap.bind("uid=#{env.user.untaint},ou=people,dc=apache,dc=org",
	env.password.untaint)

      ldap.modify person.dn, [ASF::Base.mod_replace('mail', @email.strip)]

      log = ["LDAP modify: #{ldap.err2string(ldap.err)} (#{ldap.err})"]
      if ldap.err == 0
	_transcript log
      else
	_backtrace log
      end

      ldap.unbind
    end
  end
end
